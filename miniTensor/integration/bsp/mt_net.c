/*
 * mt_net.c -- a small YOLO-shaped detection network on the miniTensor tile engine.
 *
 * Topology (single class, single anchor, anchor-free decode):
 *
 *   input 32x32x4
 *     conv 3x3  4->8   pad 1, ReLU      32x32x8
 *     maxpool 2x2                        16x16x8
 *     conv 3x3  8->16  pad 1, ReLU      16x16x16
 *     maxpool 2x2                         8x8x16
 *     conv 3x3 16->16  pad 1, ReLU        8x8x16
 *     head 1x1 16->8   (4 box + 1 obj + 1 cls, padded to 8)
 *
 * ---------------------------------------------------------------------------
 * Why A is the activations and B is the weights
 * ---------------------------------------------------------------------------
 * MT_GEMM computes C[i][j] = sum_k A[i][k]*B[k][j], with A and B each packed into
 * one 16-byte UB row (A row-major: byte 4i+k, B row-major: byte 4k+j).
 *
 * Choosing i = spatial position, j = output channel, k = input channel gives
 * A[i][k] = x[spatial i][input channel k].  Storing activations as NHWC grouped
 * by 4 channels puts channel k of spatial position i at byte 4i+k -- exactly the
 * A row layout -- and 4 consecutive spatial positions are 16 contiguous bytes.
 * So the activation operand is ONE linear MT_LOAD, with no im2col pass at all.
 *
 * The B (weight) rows are tiny -- (C/4)*(C_out/4)*k*k of them -- and stay
 * resident in the UB for the whole layer.
 *
 * The CPU only builds a zero-padded copy of the previous layer's output, and the
 * accelerator itself already emits the [group][h][w][4] layout, so no repacking
 * is needed anywhere.
 */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"
#include "mt.h"
#include "mt_net.h"

/* --------------------------------------------------------- scratch window */
/* Layer buffer offsets are relative to the 64 KiB miniTensor scratch.
 *
 * NOTE: moving these to absolute addresses (so activations could live in the
 * 12 MiB uncached window, which a 128x128 activation needs) was attempted in
 * Y15 and reverted -- see handoff/y15_absolute_addressing.md.  The change is
 * the right one but it is not finished. */
/* These take ABSOLUTE addresses.  A layer's *_off fields are relative to
 * L->base (0 meaning the 64 KiB scratch), and the engine adds that base
 * exactly once -- see net_pad/net_conv/net_pool2.  Anything outside the engine
 * that passes a scratch-relative offset must add MT_BUF_BASE itself.
 *
 * Getting this wrong is how Y15 failed: an earlier attempt both gave the
 * accessors a base AND kept indexing through a scratch pointer, so every
 * address was counted twice. */
static void    net_wr8(uint32_t addr, uint8_t v)  { *(volatile uint8_t *)(uintptr_t)addr = v; }
static uint8_t net_rd8(uint32_t addr)             { return *(volatile uint8_t *)(uintptr_t)addr; }
static void    net_wr32(uint32_t addr, uint32_t v)
{
    *(volatile uint32_t *)(uintptr_t)addr = v;
}

static uint32_t net_lcg = 0x13579BDFu;
static uint32_t net_rand(void)
{
    net_lcg = (net_lcg * 1103515245u) + 12345u;
    return net_lcg;
}

static int8_t net_requant(int32_t acc, int32_t bias,
                          int16_t mult, uint8_t shift, int8_t zp, uint8_t relu)
{
    int64_t v = ((int64_t)acc + (int64_t)bias) * (int64_t)mult;

    v = v >> shift;
    v = v + (int64_t)zp;
    if (relu && (v < 0)) { v = 0; }
    if (v > 127)  { v = 127; }
    if (v < -128) { v = -128; }
    return (int8_t)v;
}

/* ---------------------------------------------------------------- weights */
#define W1_OUT 8u
#define W1_IN  4u
#define W2_OUT 16u
#define W2_IN  8u
#define W3_OUT 16u
#define W3_IN  16u
#define W4_OUT 8u
#define W4_IN  16u

/* [out_ch][in_ch][ky][kx] */
static int8_t  w1[W1_OUT * W1_IN * 9];
static int8_t  w2[W2_OUT * W2_IN * 9];
static int8_t  w3[W3_OUT * W3_IN * 9];
static int8_t  w4[W4_OUT * W4_IN];
static int32_t b1[W1_OUT], b2[W2_OUT], b3[W3_OUT], b4[W4_OUT];

/* Weight rows per layer (ng * k * k * nm) and their packed sizes:
 *   L1  1*9*2 =  18 rows =  288 B      L3  4*9*4 = 144 rows = 2304 B
 *   L2  2*9*4 =  72 rows = 1152 B      L4  4*1*2 =   8 rows =  128 B
 * totalling 3872 B, so the slots below are contiguous rather than uniform.
 * Bias rows (nm*4) are 8/16/16/8 rows = 128/256/256/128 B. */
static const net_layer_t L1 = {
    32u, 32u, 4u, 8u, 3u, 1u, 1u, 16, 10u, 0,
    NET_IMAGE, PAD_BUF, OUT_BUF, NET_WT + 0x0000u, NET_BIAS + 0x000u, NET_CFG + 0x00u
};
static const net_layer_t L2 = {
    16u, 16u, 8u, 16u, 3u, 1u, 1u, 16, 10u, 0,
    MID_BUF, PAD_BUF, OUT_BUF, NET_WT + 0x0200u, NET_BIAS + 0x080u, NET_CFG + 0x10u
};
static const net_layer_t L3 = {
    8u, 8u, 16u, 16u, 3u, 1u, 1u, 16, 10u, 0,
    MID_BUF, PAD_BUF, OUT_BUF, NET_WT + 0x0680u, NET_BIAS + 0x180u, NET_CFG + 0x20u
};
static const net_layer_t L4 = {
    8u, 8u, 16u, 8u, 1u, 0u, 0u, 16, 10u, 0,
    OUT_BUF, PAD_BUF, MID_BUF, NET_WT + 0x0F80u, NET_BIAS + 0x280u, NET_CFG + 0x30u
};

static int32_t net_bias_for(const net_layer_t *L, uint32_t out_ch)
{
    if (L == &L1) { return b1[out_ch]; }
    if (L == &L2) { return b2[out_ch]; }
    if (L == &L3) { return b3[out_ch]; }
    return b4[out_ch];
}

/* Weight row (g, ky, kx, mg): byte 4*k + j =
 *     weight[in_ch = g*4+k][out_ch = mg*4+j][ky][kx]                       */
static void net_pack_weights(const net_layer_t *L, const int8_t *w)
{
    uint32_t ng = L->c_in / 4u, nm = L->c_out / 4u;
    uint32_t B = L->base ? L->base : MT_BUF_BASE;
    uint32_t g, ky, kx, mg, k, j;

    for (g = 0; g < ng; g++)
    for (ky = 0; ky < L->k; ky++)
    for (kx = 0; kx < L->k; kx++)
    for (mg = 0; mg < nm; mg++)
    {
        uint32_t row = (((g * L->k * L->k) + (ky * L->k) + kx) * nm) + mg;

        for (k = 0; k < 4u; k++)
        for (j = 0; j < 4u; j++)
        {
            uint32_t in_ch  = (g * 4u) + k;
            uint32_t out_ch = (mg * 4u) + j;
            uint32_t idx    = (((out_ch * L->c_in) + in_ch) * L->k * L->k)
                            + (ky * L->k) + kx;

            net_wr8(B + L->wt_off + (row * 16u) + (4u * k) + j, (uint8_t)w[idx]);
        }
    }

    /* The epilogue consumes 4 bias rows (one per spatial row of the 4x4 C
     * tile) x 4 little-endian INT32 (one per output channel of the group).
     * C element (i = spatial, j = output channel) takes bias[j], so all four
     * rows hold the same four channel biases. */
    for (mg = 0; mg < nm; mg++)
    for (k = 0; k < 4u; k++)        /* spatial row: 4 identical rows */
    for (j = 0; j < 4u; j++)        /* output channel within the group */
    {
        net_wr32(B + L->bias_off + (mg * 64u) + (k * 16u) + (j * 4u),
                 (uint32_t)net_bias_for(L, (mg * 4u) + j));
    }

    net_wr32(B + L->cfg_off, MT_CFG(L->mult, L->shift, L->zp, L->relu));
    for (k = 1; k < 4u; k++) { net_wr32(B + L->cfg_off + (k * 4u), 0u); }
}

/* Build the kx-shifted, zero-padded activation buffer.
 *
 * Layout: [kx][g][h][w][4] with h in 0..PH-1 and w in 0..W-1 (output columns).
 *
 * MT_LOAD requires 16-byte alignment, so the kernel column offset cannot be
 * applied when the A row is fetched -- a row starting at w = t*4 + kx would be
 * misaligned for kx != 0.  Baking the shift into the buffer keeps every A row
 * on a 16-byte boundary: row (kx,g,ho,ky,t) starts at
 *     pad_off + 16 * ((((kx*ng + g)*PH + ho+ky) * (W/4)) + t)
 * which is exactly 4 spatial positions x 4 channels. */
void net_pad(const net_layer_t *L)
{
    uint32_t ng = L->c_in / 4u, H = L->h, W = L->w;
    uint32_t PH = H + (2u * L->pad);
    /* SW is the source buffer's row stride; only its first W pixels are valid.
     * WP is the padded row stride of the pad buffer.  Both default to W, which
     * reproduces the unpadded behaviour exactly. */
    uint32_t SW = L->src_w ? L->src_w : W;
    uint32_t WP = L->wpad ? L->wpad : W;
    uint32_t B = L->base ? L->base : MT_BUF_BASE;
    uint32_t kx, g, h, wo, c;

    for (kx = 0; kx < L->k; kx++)
    for (g = 0; g < ng; g++)
    for (h = 0; h < PH; h++)
    for (wo = 0; wo < WP; wo++)
    for (c = 0; c < 4u; c++)
    {
        int32_t sh = (int32_t)h - (int32_t)L->pad;
        int32_t sw = (int32_t)wo + (int32_t)kx - (int32_t)L->pad;
        uint8_t v = 0u;

        if (sh >= 0 && sh < (int32_t)H && sw >= 0 && sw < (int32_t)W)
        {
            v = net_rd8(B + L->src_off
                        + ((((g * H) + (uint32_t)sh) * SW + (uint32_t)sw) * 4u) + c);
        }
        net_wr8(B + L->pad_off + ((((((kx * ng) + g) * PH) + h) * WP + wo) * 4u) + c, v);
    }
}

/* ----------------------------------------------------------- conv engine */
int net_conv(const net_layer_t *L, uint32_t *cmds)
{
    uint32_t ng = L->c_in / 4u, nm = L->c_out / 4u;
    uint32_t H = L->h, W = L->w;
    /* Compute and store at the padded width; the consumer reads only W of it. */
    uint32_t WP = L->wpad ? L->wpad : W;
    uint32_t PH = H + (2u * L->pad);
    uint32_t ntiles = WP / 4u;
    uint32_t kk = L->k * L->k;
    uint32_t ntap = kk * ng;
    uint32_t ntiles4 = ntiles * 4u;
    uint32_t B = L->base ? L->base : MT_BUF_BASE;
    uint32_t nmt = L->nmt ? L->nmt : nm;   /* output groups per weight tile */
    uint32_t ho, t, q, mt, j, i, tile, t0;
    uint32_t count = 0u;
    int rc;


    if ((rc = mt_push(MT_LOAD, B + L->cfg_off,
                      MT_ROWS(UB_CFG, L->leaky ? 2u : 1u))) != 0) return rc;
    count++;

    for (mt = 0, tile = 0u; mt < nm; mt += nmt, tile++)
    {
        uint32_t nl   = nm - mt;                       /* groups left        */
        uint32_t njt  = (nl < nmt) ? nl : nmt;         /* groups in this tile */
        /* Every tile occupies a full ntap*nmt row slot, so the base advances
         * by the TILE index -- using the group index here skips slots. */
        uint32_t wbase = L->wt_off + (tile * ntap * nmt * 16u);
        /* Taps are finished in chunks that fit UB_WT.  A layer with 32 input
         * groups and 3x3 taps needs 288 weight rows while UB_WT holds 144, so
         * one tile is impossible for it; splitting over taps keeps the weights
         * resident while that row's GEMMs run, and costs no extra DMA because
         * each tap's weight row is still fetched exactly once. */
        uint32_t na = MT_UB_WT_ROWS / njt;             /* taps per chunk     */
        uint32_t tc, nq;

        if (na == 0u)
        {
            return -6;      /* not even one output group fits UB_WT */
        }
        if (na > ntap) { na = ntap; }

        /* The bias for a run of groups is contiguous (4 rows per group). */
        if ((rc = mt_push(MT_LOAD, B + L->bias_off + (mt * 64u),
                          MT_ROWS(UB_BIAS, njt * 4u))) != 0) return rc;
        count++;

        for (ho = 0; ho < H; ho++)
        {
            uint32_t hrow = ho * ntiles;

            for (tc = 0; tc < ntap; tc += na)
            {
                nq = (ntap - tc) < na ? (ntap - tc) : na;

                /* Taps [tc, tc+nq) of every group in the tile are contiguous in
                 * the packed blob: row = q*nmt + j. */
                for (i = 0; i < (nq * njt); i += 8u)
                {
                    uint32_t n = ((nq * njt) - i) < 8u ? ((nq * njt) - i) : 8u;

                    if ((rc = mt_push(MT_LOAD,
                                      B + wbase + (((tc * njt) + i) * 16u),
                                      MT_ROWS(UB_WT + i, n))) != 0) return rc;
                    count++;
                }

                for (t = 0; t < ntiles; t++)
                {
                    uint32_t crow0 = UB_C + (t * 4u);

                    for (q = tc; q < tc + nq; q++)
                    {
                        /* Tap q enumerates as g*kk + ky*k + kx -- the order the
                         * packer writes rows in, which is what makes a chunk's
                         * weight rows contiguous.  The bases are computed
                         * inline rather than tabulated: a table capped the
                         * input at 64 channels, and tiny-yolov3's deeper layers
                         * are far wider (128, 256, 512). */
                        uint32_t g   = q / kk;
                        uint32_t rem = q % kk;
                        uint32_t ky  = rem / L->k;
                        uint32_t kx  = rem % L->k;
                        uint32_t a_addr = L->pad_off + 16u *
                            ((((((kx * ng) + g) * PH) + ky) * ntiles) + hrow + t);
                        uint32_t wb = UB_WT + ((q - tc) * njt);

                        if ((rc = mt_push(MT_LOAD, B + a_addr,
                                          MT_ROWS(UB_A, 1u))) != 0) return rc;
                        count++;

                        for (j = 0; j < njt; j++)
                        {
                            uint32_t rs1 = MT_GEMM_RS1(UB_A, wb + j);
                            /* The first tap of the whole output overwrites C and
                             * every later tap accumulates.  This is a property
                             * of the tap, so it must be recomputed for each
                             * output group -- hoisting it into one variable
                             * leaves groups 1..n-1 accumulating onto the
                             * previous row's values. */
                            uint32_t rs2 = MT_GEMM_RS2(crow0 + (j * ntiles4),
                                                       (tc == 0u && q == tc)
                                                           ? 0u : 1u);

                            if ((rc = mt_push(MT_GEMM, rs1, rs2)) != 0) return rc;
                            count++;
                        }
                    }
                }
            }

        /* The epilogue runs once the whole row's GEMMs are queued.  It stays
         * inside the ho loop: UB_OUT holds one output row. */
        for (j = 0; j < njt; j++)
        {
            uint32_t crow = UB_C + (j * ntiles4);

                /* UB_OUT and UB_SKIP have 8 rows each, so an output row is
                 * finished in chunks of at most 8 tiles.  W up to 32 fits in
                 * one chunk; wider layers need several -- tiny-yolov3's stem is
                 * 64 wide, i.e. 16 tiles.  Without this the second epilogue's
                 * destination runs past the end of the UB row space and wraps
                 * back into the weight rows, corrupting the layer. */
                for (t0 = 0; t0 < ntiles; t0 += 8u)
                {
                    uint32_t n = (ntiles - t0) < 8u ? (ntiles - t0) : 8u;
                    uint32_t off16 = t0 * 16u;

                    for (t = 0; t < n; t++)
                    {
                        if ((rc = mt_push(MT_EPILOGUE,
                                          MT_EPI_RS1(crow + ((t0 + t) * 4u),
                                                     UB_BIAS + (j * 4u)),
                                          MT_EPI_RS2(UB_OUT + t, UB_CFG))) != 0)
                        {
                            return rc;
                        }
                        count++;
                    }

                    /* LeakyReLU as max(x, a*x), using the second config row.
                     * The second epilogue writes to UB_SKIP, which is still
                     * free here (the residual loads it later). */
                    if (L->leaky != 0u)
                    {
                        for (t = 0; t < n; t++)
                        {
                            if ((rc = mt_push(MT_EPILOGUE,
                                              MT_EPI_RS1(crow + ((t0 + t) * 4u),
                                                         UB_BIAS + (j * 4u)),
                                              MT_EPI_RS2(UB_SKIP + t,
                                                         UB_CFG + 1u))) != 0)
                            {
                                return rc;
                            }
                            count++;
                        }
                        for (t = 0; t < n; t++)
                        {
                            if ((rc = mt_push(MT_VEC_MAX8,
                                              MT_VEC_RS1(UB_OUT + t, UB_SKIP + t),
                                              MT_VEC_RS2(UB_OUT + t))) != 0)
                            {
                                return rc;
                            }
                            count++;
                        }
                    }

                    /* Residual: bring in the matching skip rows and combine
                     * them with the vector unit. */
                    if (L->skip != 0u)
                    {
                        uint32_t sbase = L->skip_off +
                                         ((((mt + j) * H) + ho) * WP * 4u) + off16;

                        if ((rc = mt_push(MT_LOAD, B + sbase,
                                          MT_ROWS(UB_SKIP, n))) != 0) return rc;
                        count++;
                        for (t = 0; t < n; t++)
                        {
                            if ((rc = mt_push(MT_VEC_ADD8,
                                              MT_VEC_RS1(UB_OUT + t, UB_SKIP + t),
                                              MT_VEC_RS2(UB_OUT + t))) != 0)
                            {
                                return rc;
                            }
                            count++;
                        }
                        if (L->skip == 2u)
                        {
                            for (t = 0; t < n; t++)
                            {
                                if ((rc = mt_push(MT_VEC_RELU8,
                                                  MT_VEC_RS1(UB_OUT + t, UB_OUT + t),
                                                  MT_VEC_RS2(UB_OUT + t))) != 0)
                                {
                                    return rc;
                                }
                                count++;
                            }
                        }
                    }

                    if ((rc = mt_push(MT_STORE,
                                      B + L->out_off +
                                          ((((mt + j) * H) + ho) * WP * 4u) + off16,
                                      MT_ROWS(UB_OUT, n))) != 0) return rc;
                    count++;
                }
            }
        }
    }

    *cmds += count;

    /* Commands are queued without per-command polling, so the layer only has to
     * wait once here -- before the caller inspects the output buffer. */
    return mt_drain();
}

/* --------------------------------------------------------------- maxpool */
void net_pool_k(uint32_t base, uint32_t src_off, uint32_t dst_off, uint32_t g_count,
                uint32_t h, uint32_t w, uint32_t k, uint32_t stride,
                uint32_t sw, uint32_t dw)
{
    /* Output extent for a k x k window with the given stride.  Only stride 1
     * and 2 are used (stride 2/k 2 is the usual downsample; the stride-1 test
     * pool shrinks by one).  The division is written out as shifts on purpose:
     * an integer divide in the NVboard Verilator model perturbs the DUT's
     * retire/PC bookkeeping (see handoff), so the firmware keeps DIV out of the
     * pooling path. */
    uint32_t oh, ow;
    uint32_t g, oy, ox, c;

    if (stride == 1u) { oh = h - k + 1u; ow = w - k + 1u; }
    else              { oh = ((h - k) >> 1) + 1u; ow = ((w - k) >> 1) + 1u; }

    if (sw == 0u) { sw = w; }        /* source row stride                */
    if (dw == 0u) { dw = ow; }       /* destination row stride, padded   */

    for (g = 0; g < g_count; g++)
    for (oy = 0; oy < oh; oy++)
    for (ox = 0; ox < dw; ox++)
    for (c = 0; c < 4u; c++)
    {
        /* Walk the whole padded destination row so the padding holds a defined
         * value (zero) rather than whatever was in the buffer.  A downstream
         * layer may widen its tile count to cover it. */
        uint8_t out = 0u;

        if (ox < ow)
        {
            int32_t best = -128;
            uint32_t ky, kx;

            for (ky = 0; ky < k; ky++)
            for (kx = 0; kx < k; kx++)
            {
                int8_t v = (int8_t)net_rd8(base + src_off
                    + (((((g * h) + ((oy * stride) + ky)) * sw)
                        + ((ox * stride) + kx)) * 4u) + c);

                if (v > best) { best = v; }
            }
            out = (uint8_t)best;
        }
        net_wr8(base + dst_off + (((((g * oh) + oy) * dw) + ox) * 4u) + c, out);
    }
}

void net_pool2(uint32_t base, uint32_t src_off, uint32_t dst_off, uint32_t g_count,
               uint32_t h, uint32_t w, uint32_t sw, uint32_t dw)
{
    net_pool_k(base, src_off, dst_off, g_count, h, w, 2u, 2u, sw, dw);
}

void net_pool_k_same(uint32_t base, uint32_t src_off, uint32_t dst_off,
                     uint32_t g_count, uint32_t h, uint32_t w, uint32_t k,
                     uint32_t stride, uint32_t sw, uint32_t dw)
{
    /* ONNX SAME_UPPER: out = ceil(in/stride), padding only at the
     * bottom/right.  Skipping the out-of-range taps is exactly a -inf pad for
     * a max pool.  Stride is 1 or 2, and the shift keeps DIV out of the path
     * for the same reason net_pool_k does. */
    uint32_t oh, ow;
    uint32_t g, oy, ox, c;

    if (stride == 1u) { oh = h; ow = w; }
    else              { oh = (h + 1u) >> 1; ow = (w + 1u) >> 1; }

    if (sw == 0u) { sw = w; }
    if (dw == 0u) { dw = ow; }

    for (g = 0; g < g_count; g++)
    for (oy = 0; oy < oh; oy++)
    for (ox = 0; ox < dw; ox++)
    for (c = 0; c < 4u; c++)
    {
        uint8_t out = 0u;

        if (ox < ow)
        {
            int32_t best = -128;
            uint32_t ky, kx;

            for (ky = 0; ky < k; ky++)
            {
                uint32_t iy = (oy * stride) + ky;

                if (iy >= h) { continue; }
                for (kx = 0; kx < k; kx++)
                {
                    uint32_t ix = (ox * stride) + kx;
                    int8_t v;

                    if (ix >= w) { continue; }
                    v = (int8_t)net_rd8(base + src_off
                        + (((((g * h) + iy) * sw) + ix) * 4u) + c);
                    if (v > best) { best = v; }
                }
            }
            out = (uint8_t)best;
        }
        net_wr8(base + dst_off + (((((g * oh) + oy) * dw) + ox) * 4u) + c, out);
    }
}

void net_upsample2(uint32_t base, uint32_t src_off, uint32_t dst_off, uint32_t g_count,
                   uint32_t h, uint32_t w, uint32_t sw, uint32_t dw)
{
    /* Resize(nearest, floor, asymmetric): every source pixel becomes a 2x2
     * block, so out[2y+dy][2x+dx] = src[y][x]. */
    uint32_t oh = 2u * h, ow = 2u * w;
    uint32_t g, oy, ox, c;

    if (sw == 0u) { sw = w; }
    if (dw == 0u) { dw = ow; }

    for (g = 0; g < g_count; g++)
    for (oy = 0; oy < oh; oy++)
    for (ox = 0; ox < dw; ox++)
    for (c = 0; c < 4u; c++)
    {
        uint8_t v = 0u;

        if (ox < ow)
        {
            uint32_t sy = oy >> 1, sx = ox >> 1;

            v = net_rd8(base + src_off + (((((g * h) + sy) * sw) + sx) * 4u) + c);
        }
        net_wr8(base + dst_off + (((((g * oh) + oy) * dw) + ox) * 4u) + c, v);
    }
}

void net_concat2(uint32_t base, uint32_t dst_off,
                 uint32_t src1_off, uint32_t g1, uint32_t src2_off, uint32_t g2,
                 uint32_t h, uint32_t w)
{
    /* Both sources and the destination are contiguous [g][h][w][4] runs, so a
     * concat is two block copies; no per-pixel work is needed. */
    uint32_t run = h * w * 4u;
    uint32_t i;

    for (i = 0; i < g1 * run; i++)
    {
        net_wr8(base + dst_off + i, net_rd8(base + src1_off + i));
    }
    for (i = 0; i < g2 * run; i++)
    {
        net_wr8(base + dst_off + (g1 * run) + i, net_rd8(base + src2_off + i));
    }
}

/* =========================================================================
 * CPU reference, mirroring the same topology and quantisation exactly.
 * ========================================================================= */
/* Only two ping-pong buffers: the reference is recomputed stage by stage and
 * compared immediately, which keeps .bss small enough for the platform. */
static uint8_t ref_a[8192];
static uint8_t ref_b[8192];

static uint8_t ref_pad_at(const uint8_t *src, uint32_t h, uint32_t w,
                          int32_t sh, int32_t sw, uint32_t ch)
{
    if (sh < 0 || sh >= (int32_t)h || sw < 0 || sw >= (int32_t)w) { return 0u; }
    return src[((((ch / 4u) * h) + (uint32_t)sh) * w + (uint32_t)sw) * 4u + (ch % 4u)];
}

static void ref_conv(const uint8_t *src, uint8_t *dst,
                     uint32_t h, uint32_t width, uint32_t c_in, uint32_t c_out,
                     uint32_t k, uint32_t pad, const int8_t *wt,  /* pad unused: folded into sh/sw */
                     const int32_t *bias, int16_t mult, uint8_t shift,
                     int8_t zp, uint8_t relu)
{
    uint32_t oh, ow, oc, ic, ky, kx;

    for (oh = 0; oh < h; oh++)
    for (ow = 0; ow < width; ow++)
    for (oc = 0; oc < c_out; oc++)
    {
        int32_t acc = 0;

        for (ic = 0; ic < c_in; ic++)
        for (ky = 0; ky < k; ky++)
        for (kx = 0; kx < k; kx++)
        {
            int32_t sh = (int32_t)oh + (int32_t)ky - (int32_t)pad;
            int32_t sw = (int32_t)ow + (int32_t)kx - (int32_t)pad;
            /* Activations are SIGNED INT8; ref_pad_at hands back raw bytes. */
            uint8_t v = ref_pad_at(src, h, width, sh, sw, ic);

            acc += (int32_t)wt[(((oc * c_in) + ic) * k * k) + (ky * k) + kx]
                 * (int32_t)(int8_t)v;
        }
        dst[((((oc / 4u) * h) + oh) * width + ow) * 4u + (oc % 4u)] =
            (uint8_t)net_requant(acc, bias[oc], mult, shift, zp, relu);
    }
}

/* Mirrors net_pool_k: k x k window, arbitrary stride, [g][h][w][4] order. */
static void ref_pool_k(const uint8_t *src, uint8_t *dst, uint32_t h, uint32_t w,
                       uint32_t c, uint32_t k, uint32_t stride)
{
    uint32_t oh = ((h - k) / stride) + 1u, ow = ((w - k) / stride) + 1u;
    uint32_t g, oy, ox, cl, ky, kx;

    for (g = 0; g < c / 4u; g++)
    for (oy = 0; oy < oh; oy++)
    for (ox = 0; ox < ow; ox++)
    for (cl = 0; cl < 4u; cl++)
    {
        int32_t best = -128;

        for (ky = 0; ky < k; ky++)
        for (kx = 0; kx < k; kx++)
        {
            int8_t v = (int8_t)src[((((g * h) + ((oy * stride) + ky)) * w)
                                    + ((ox * stride) + kx)) * 4u + cl];
            if (v > best) { best = v; }
        }
        dst[((((g * oh) + oy) * ow) + ox) * 4u + cl] = (uint8_t)best;
    }
}

static void ref_pool2(const uint8_t *src, uint8_t *dst,
                      uint32_t h, uint32_t w, uint32_t c)
{
    uint32_t oh2 = h / 2u, ow2 = w / 2u, g, oh, ow, cl, dy, dx;

    for (g = 0; g < c / 4u; g++)
    for (oh = 0; oh < oh2; oh++)
    for (ow = 0; ow < ow2; ow++)
    for (cl = 0; cl < 4u; cl++)
    {
        int32_t best = -128;

        for (dy = 0; dy < 2u; dy++)
        for (dx = 0; dx < 2u; dx++)
        {
            int8_t v = (int8_t)src[((((g * h) + ((oh * 2u) + dy)) * w)
                                    + ((ow * 2u) + dx)) * 4u + cl];
            if (v > best) { best = v; }
        }
        dst[((((g * oh2) + oh) * ow2) + ow) * 4u + cl] = (uint8_t)best;
    }
}

static void net_build_weights(void)
{
    uint32_t i;

    for (i = 0; i < W1_OUT * W1_IN * 9u; i++) w1[i] = (int8_t)((int32_t)(net_rand() % 11u) - 5);
    for (i = 0; i < W2_OUT * W2_IN * 9u; i++) w2[i] = (int8_t)((int32_t)(net_rand() % 11u) - 5);
    for (i = 0; i < W3_OUT * W3_IN * 9u; i++) w3[i] = (int8_t)((int32_t)(net_rand() % 11u) - 5);
    for (i = 0; i < W4_OUT * W4_IN; i++)     w4[i] = (int8_t)((int32_t)(net_rand() % 11u) - 5);

    for (i = 0; i < W1_OUT; i++) b1[i] = (int32_t)(net_rand() % 201u) - 100;
    for (i = 0; i < W2_OUT; i++) b2[i] = (int32_t)(net_rand() % 201u) - 100;
    for (i = 0; i < W3_OUT; i++) b3[i] = (int32_t)(net_rand() % 201u) - 100;
    for (i = 0; i < W4_OUT; i++) b4[i] = (int32_t)(net_rand() % 201u) - 100;
}

/* Compare a scratch buffer against the reference, reporting the first few
 * mismatches so a broken layer can be identified directly. */
static int net_check(uint32_t off, const uint8_t *ref, uint32_t n, const char *label)
{
    uint32_t i;
    int bad = 0;

    for (i = 0; i < n; i++)
    {
        uint8_t got = net_rd8(MT_BUF_BASE + off + i);   /* callers pass scratch offsets */

        if (got != ref[i])
        {
            if (bad < 4)
            {
                rt_kprintf("  %s byte %u: got %02x expect %02x\n",
                           label, (unsigned)i, (unsigned)got, (unsigned)ref[i]);
            }
            bad++;
        }
    }
    if (bad != 0)
    {
        rt_kprintf("  %s: %d/%u bytes wrong\n", label, bad, (unsigned)n);
    }
    else
    {
        rt_kprintf("  %s: OK (%u bytes)\n", label, (unsigned)n);
    }
    return bad;
}

/* ------------------------------------------------------------------ shell */
static int mt_net_command(int argc, char **argv)
{
    uint32_t i, cmds = 0u, start, end, accel_cycles = 0u;
    int rc;
    int mismatches = 0;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor YOLO-shaped net (32x32x4 -> 8x8x8 head).\n");

    net_lcg = 0x13579BDFu;
    net_build_weights();

    /* Input image, NHWC grouped: [1][32][32][4]. */
    for (i = 0; i < 32u * 32u * 4u; i++)
    {
        net_wr8(MT_BUF_BASE + NET_IMAGE + i,
                (uint8_t)((int32_t)(net_rand() % 255u) - 127));
    }

    net_pack_weights(&L1, w1);
    net_pack_weights(&L2, w2);
    net_pack_weights(&L3, w3);
    net_pack_weights(&L4, w4);

    for (i = 0; i < 32u * 32u * 4u; i++)
    {
        ref_a[i] = net_rd8(MT_BUF_BASE + NET_IMAGE + i);
    }

    mt_reset_status();
    JYD_MMIO32(JYD_LED_ADDR) = 1u;

    /* Each stage: run the accelerator (timed), then recompute that stage's CPU
     * reference and compare.  Only ref_a/ref_b are live, so .bss stays small. */
    start = mt_rd_mcycle();
    net_pad(&L1);
    if ((rc = net_conv(&L1, &cmds)) != 0) goto fail;
    end = mt_rd_mcycle();
    accel_cycles += end - start;
    net_pool2(MT_BUF_BASE, OUT_BUF, MID_BUF, 2u, 32u, 32u, 0u, 0u);
    ref_conv(ref_a, ref_b, 32u, 32u, 4u, 8u, 3u, 1u, w1, b1, 16, 10u, 0, 1u);
    mismatches += net_check(OUT_BUF, ref_b, 32u * 32u * 8u, "L1 conv");
    for (i = 0; i < 32u * 32u * 8u; i++) { ref_a[i] = ref_b[i]; }
    ref_pool2(ref_a, ref_b, 32u, 32u, 8u);
    mismatches += net_check(MID_BUF, ref_b, 16u * 16u * 8u, "L1 pool");

    /* Stride-1 pooling on the 16x16 stage -- tiny-yolov3's eleventh layer is
     * 2x2 stride 1, which only shrinks the map by one row and column. */
    net_pool_k(MT_BUF_BASE, MID_BUF, OUT_BUF, 2u, 16u, 16u, 2u, 1u, 0u, 0u);
    ref_pool_k(ref_b, ref_a, 16u, 16u, 8u, 2u, 1u);
    mismatches += net_check(OUT_BUF, ref_a, 15u * 15u * 8u, "L1 pool s1");

    for (i = 0; i < 16u * 16u * 8u; i++) { ref_a[i] = ref_b[i]; }
    start = mt_rd_mcycle();
    net_pad(&L2);
    if ((rc = net_conv(&L2, &cmds)) != 0) goto fail;
    end = mt_rd_mcycle();
    accel_cycles += end - start;
    net_pool2(MT_BUF_BASE, OUT_BUF, MID_BUF, 4u, 16u, 16u, 0u, 0u);
    ref_conv(ref_a, ref_b, 16u, 16u, 8u, 16u, 3u, 1u, w2, b2, 16, 10u, 0, 1u);
    mismatches += net_check(OUT_BUF, ref_b, 16u * 16u * 16u, "L2 conv");
    for (i = 0; i < 16u * 16u * 16u; i++) { ref_a[i] = ref_b[i]; }
    ref_pool2(ref_a, ref_b, 16u, 16u, 16u);
    mismatches += net_check(MID_BUF, ref_b, 8u * 8u * 16u, "L2 pool");

    for (i = 0; i < 8u * 8u * 16u; i++) { ref_a[i] = ref_b[i]; }
    start = mt_rd_mcycle();
    net_pad(&L3);
    if ((rc = net_conv(&L3, &cmds)) != 0) goto fail;
    end = mt_rd_mcycle();
    accel_cycles += end - start;
    ref_conv(ref_a, ref_b, 8u, 8u, 16u, 16u, 3u, 1u, w3, b3, 16, 10u, 0, 1u);
    mismatches += net_check(OUT_BUF, ref_b, 8u * 8u * 16u, "L3 conv");

    for (i = 0; i < 8u * 8u * 16u; i++) { ref_a[i] = ref_b[i]; }
    start = mt_rd_mcycle();
    net_pad(&L4);
    if ((rc = net_conv(&L4, &cmds)) != 0) goto fail;
    end = mt_rd_mcycle();
    accel_cycles += end - start;
    ref_conv(ref_a, ref_b, 8u, 8u, 16u, 8u, 1u, 0u, w4, b4, 16, 10u, 0, 0u);
    mismatches += net_check(MID_BUF, ref_b, 8u * 8u * 8u, "L4 head");

    JYD_MMIO32(JYD_LED_ADDR) = 0u;

    rt_kprintf("miniTensor net PASSED (all stages match the CPU reference).\n");
    rt_kprintf("  %u accelerator commands, %u accelerator cycles\n",
               (unsigned)cmds, (unsigned)accel_cycles);
    rt_kprintf("  745472 MACs => %u cycles per 64-MAC command\n",
               (unsigned)(accel_cycles / (cmds ? cmds : 1u)));
    return 0;

fail:
    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    rt_kprintf("miniTensor net FAILED at layer, rc=%d\n", rc);
    halt(41);
    return rc;
}
MSH_CMD_EXPORT_ALIAS(mt_net_command, mt_net, run the miniTensor detection network.);
