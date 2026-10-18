/*
 * mt_wide.c -- weight streaming through a layer that does not fit in UB.
 *
 * A 3x3 convolution with 48 input and 48 output channels over an 8x8 map needs
 * 12*9*12 = 1296 weight rows (20736 bytes).  UB_WT holds 144 rows, so this is
 * 9x over capacity.  net_conv handles it by reloading the weights once per
 * output-group tile (nmt=1 here, so 12 tiles), which is exactly what a wide
 * YOLO layer requires.
 *
 * Before weight tiling existed this layer was simply not expressible: net_conv
 * loaded every weight row up front and rejected anything over 144 rows.
 *
 * The reference is the integer model from pack_wide.py, so the check is
 * bit-exact.
 */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"
#include "mt.h"
#include "mt_net.h"
#include "mt_wide_weights.h"

/* Scratch layout inside the 64 KiB uncached alias.
 *
 * NOTE: the bias block is nm*4 = 48 rows = 768 bytes, so it runs from 0x8200 to
 * 0x84FF.  WIDE_CFG used to sit at 0x8400, i.e. 512 bytes in -- which is
 * exactly where group 8's bias rows begin.  The config word then became group
 * 8's bias row 0 (= spatial row 0), and since the epilogue adds bias row r to C
 * row r, output channel 32 at the first pixel of every tile saturated.  Keep
 * every block clear of the next one. */
#define WIDE_PAD    0x0000u   /* 3*12*10*8*4  = 11520 B -> 0x2D00 */
#define WIDE_WT    0x3000u   /* 1296 rows    = 20736 B -> 0x8100 */
#define WIDE_BIAS    0x8200u   /* 48 rows      =   768 B -> 0x8500 */
#define WIDE_CFG    0x8600u   /*   1 row      =    16 B -> 0x8610 */
#define WIDE_IMG    0x8800u   /* 3072 B                 -> 0x9400 */
#define WIDE_OUT    0x9400u   /* 3072 B                 -> 0xA000 */

#define WIDE_IMG_BYTES (WIDE_H * WIDE_W * WIDE_C_IN)

/* Compile-time proof that the scratch blocks do not overlap.  This is the check
 * that was missing when WIDE_CFG sat at 0x8400, inside WIDE_BIAS, silently
 * turning the config word into group 8's bias row 0.  A mis-sized block is now
 * a build error instead of a 16-byte mystery at runtime. */
#define MT_SA(cond, tag) typedef char mt_sa_##tag[(cond) ? 1 : -1]
MT_SA(WIDE_PAD + (3u * (WIDE_C_IN / 4u) * ((WIDE_H + 2u) * WIDE_W * 4u)) <= WIDE_WT,
      pad_ends_before_wt);
MT_SA(WIDE_WT + sizeof(wide_wt) <= WIDE_BIAS, wt_ends_before_bias);
MT_SA(WIDE_BIAS + sizeof(wide_bias) <= WIDE_CFG, bias_ends_before_cfg);
MT_SA(WIDE_CFG + sizeof(wide_cfg) <= WIDE_IMG, cfg_ends_before_img);
MT_SA(WIDE_IMG + sizeof(wide_img) <= WIDE_OUT, img_ends_before_out);
MT_SA(WIDE_OUT + sizeof(wide_gold) <= MT_BUF_SIZE, out_fits_in_scratch);

static volatile uint8_t *const wide_buf = (volatile uint8_t *)(uintptr_t)MT_BUF_BASE;

static void wide_stage(uint32_t off, const unsigned char *src, uint32_t n)
{
    uint32_t i;

    for (i = 0; i < n; i++)
    {
        wide_buf[off + i] = src[i];
    }
}

static int mt_wide_command(int argc, char **argv)
{
    net_layer_t L;
    uint32_t cmds = 0u, start, end, i, bad = 0u;
    uint32_t word;
    int rc;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor wide layer: 8x8x%d -> 8x8x%d, k=3 (weights %u B).\n",
               (int)WIDE_C_IN, (int)WIDE_C_OUT, (unsigned)sizeof(wide_wt));

    /* Stage everything into uncached memory: the DMA cannot see .rodata. */
    wide_stage(WIDE_WT,   wide_wt,   sizeof(wide_wt));
    wide_stage(WIDE_BIAS, wide_bias, sizeof(wide_bias));
    wide_stage(WIDE_CFG,  wide_cfg,  sizeof(wide_cfg));
    wide_stage(WIDE_IMG,  wide_img,  sizeof(wide_img));

    word = (uint32_t)wide_cfg[0] | ((uint32_t)wide_cfg[1] << 8) |
           ((uint32_t)wide_cfg[2] << 16) | ((uint32_t)wide_cfg[3] << 24);

    L = (net_layer_t){WIDE_H, WIDE_W, WIDE_C_IN, WIDE_C_OUT, 3u, 1u, 1u, 0, 0u, 0,
                      WIDE_IMG, WIDE_PAD, WIDE_OUT,
                      WIDE_WT, WIDE_BIAS, WIDE_CFG, 0u};
    L.mult  = (int16_t)(word & 0xFFFFu);
    L.shift = (uint8_t)((word >> 16) & 0x1Fu);
    L.zp    = (int8_t)((word >> 21) & 0xFFu);
    L.relu  = (uint8_t)((word >> 29) & 0x1u);
    L.nmt   = wide_cfg[4];

    rt_kprintf("  weight tile size nmt=%u -> %u tiles of %u rows each.\n",
               (unsigned)L.nmt,
               (unsigned)((WIDE_C_OUT / 4u + L.nmt - 1u) / L.nmt),
               (unsigned)((L.k * L.k) * (WIDE_C_IN / 4u) * L.nmt));

    {
        uint32_t a = 0u, b = 0u, c = 0u, d = 0u;

        for (i = 0; i < sizeof(wide_wt); i++)
        {
            a += wide_buf[WIDE_WT + i];
            if ((i % 16u) == 0u) { b += wide_buf[WIDE_WT + i]; }
            if ((i >= 8u * 108u * 16u) && (i < 9u * 108u * 16u) &&
                ((i % 16u) == 0u)) { c += wide_buf[WIDE_WT + i]; }
        }
        for (i = 0; i < WIDE_IMG_BYTES; i++) { d += wide_buf[WIDE_IMG + i]; }
        rt_kprintf("  staged wt checksum: all=%08x lane0=%08x tile8lane0=%08x\n",
                   (unsigned)a, (unsigned)b, (unsigned)c);
        rt_kprintf("  staged img checksum: %08x\n", (unsigned)d);
    }

    mt_reset_status();
    start = mt_rd_mcycle();
    JYD_MMIO32(JYD_LED_ADDR) = 1u;

    for (i = 0; i < 1u; i++)
    {
        uint32_t z;

        for (z = 0; z < WIDE_OUT_BYTES; z++)
        {
            wide_buf[WIDE_OUT + z] = (uint8_t)(0x55u + i);
        }

        net_pad(&L);
        if ((rc = net_conv(&L, &cmds)) != 0)
        {
            JYD_MMIO32(JYD_LED_ADDR) = 0u;
            rt_kprintf("miniTensor wide layer FAILED, rc=%d\n", rc);
            halt(60);
            return rc;
        }

        {
            uint32_t nb = 0u, first = 0xFFFFFFFFu;

            for (z = 0; z < WIDE_OUT_BYTES; z++)
            {
                if (wide_buf[WIDE_OUT + z] != wide_gold[z])
                {
                    if (first == 0xFFFFFFFFu) { first = z; }
                    nb++;
                }
            }
            rt_kprintf("  pass %u: %u/%u bytes differ (first at %u)\n",
                       (unsigned)i, (unsigned)nb, (unsigned)WIDE_OUT_BYTES,
                       (unsigned)first);
        }
    }

    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    end = mt_rd_mcycle();

    for (i = 0; i < WIDE_OUT_BYTES; i++)
    {
        uint8_t got = wide_buf[WIDE_OUT + i];

        if (got != wide_gold[i])
        {
            if (bad < 4u)
            {
                uint32_t per_grp = (uint32_t)WIDE_H * WIDE_W * 4u;

                rt_kprintf("  byte %u (grp %u, h %u, w %u, c %u): got %02x expect %02x\n",
                           (unsigned)i, (unsigned)(i / per_grp),
                           (unsigned)((i / 4u / WIDE_W) % WIDE_H),
                           (unsigned)((i / 4u) % WIDE_W), (unsigned)(i % 4u),
                           (unsigned)got, (unsigned)wide_gold[i]);
            }
            bad++;
        }
    }

    if (bad != 0u)
    {
        rt_kprintf("miniTensor wide layer FAILED: %u/%u bytes differ\n",
                   (unsigned)bad, (unsigned)WIDE_OUT_BYTES);
        return -1;
    }

    rt_kprintf("miniTensor wide layer PASSED (%u/%u bytes, %u commands, %u cycles)\n",
               (unsigned)WIDE_OUT_BYTES, (unsigned)WIDE_OUT_BYTES,
               (unsigned)cmds, (unsigned)(end - start));
    return 0;
}
MSH_CMD_EXPORT_ALIAS(mt_wide_command, mt_wide, stream a layer larger than UB.);
