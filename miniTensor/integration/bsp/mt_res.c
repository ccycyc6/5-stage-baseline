/*
 * mt_res.c -- residual (skip) connection through the VPU.
 *
 * Runs a basic ResNet / CSPDarknet bottleneck core:
 *
 *     y = relu( conv3x3( relu(conv3x3(x)) ) + x )
 *
 * The first convolution applies ReLU in its epilogue; the second does not,
 * because the residual add happens after it and the final ReLU is applied once,
 * to the sum.  Both the add and that ReLU are MT_VECTOR operations on the UB --
 * this is the first network in the project to use the vector unit for real work
 * rather than in a self-check.
 *
 * The reference is the integer model from pack_res.py, so the check is bit-exact.
 * The operands are scaled so the sum does reach the int8 limits, which pins down
 * a property worth knowing: ADD8 WRAPS (vpu_vector_alu.sv:22 is a plain 8-bit
 * add), so a residual branch must be scaled to stay in range -- overflow folds
 * the sign instead of clamping.  Here we want the wrap to happen, because the
 * point is to verify the hardware's actual behaviour. */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"
#include "mt.h"
#include "mt_net.h"
#include "mt_res_weights.h"

/* Scratch layout inside the 64 KiB uncached alias.  The compile-time asserts
 * below keep every block clear of the next one -- see handoff/y7 for why. */
#define RES_PAD    0x0000u   /* 3*4*10*8*4 = 3840 B -> 0x0F00 */
#define RES_WT    0x1000u   /* 144 rows   = 2304 B -> 0x1900 */
#define RES_WT2    0x1A00u   /* 144 rows   = 2304 B -> 0x2300 */
#define RES_BIAS    0x2400u   /*  16 rows   =  256 B -> 0x2500 */
#define RES_BIAS2    0x2600u   /*  16 rows   =  256 B -> 0x2700 */
#define RES_CFG    0x2800u   /*   1 row    =   16 B -> 0x2810 */
#define RES_CFG2   0x2820u
#define RES_IMG    0x3000u   /* 8*8*16     = 1024 B -> 0x3400 */
#define RES_H1    0x3400u   /* 8*8*16     = 1024 B -> 0x3800 */
#define RES_OUT    0x3800u   /* 8*8*16     = 1024 B -> 0x3C00 */

#define MT_SA(cond, tag) typedef char mt_sa_##tag[(cond) ? 1 : -1]
MT_SA(RES_PAD + (3u * (RES_C / 4u) * ((RES_H + 2u) * RES_W * 4u)) <= RES_WT, pad_wt);
MT_SA(RES_WT + sizeof(res_wt1) <= RES_WT2, wt1_wt2);
MT_SA(RES_WT2 + sizeof(res_wt2) <= RES_BIAS, wt2_bias);
MT_SA(RES_BIAS + sizeof(res_bias1) <= RES_BIAS2, bias1_bias2);
MT_SA(RES_BIAS2 + sizeof(res_bias2) <= RES_CFG, bias2_cfg);
MT_SA(RES_CFG + sizeof(res_cfg1) <= RES_CFG2, cfg1_cfg2);
MT_SA(RES_CFG2 + sizeof(res_cfg2) <= RES_IMG, cfg2_img);
MT_SA(RES_IMG + sizeof(res_img) <= RES_H1, img_h1);
MT_SA(RES_H1 + sizeof(res_img) <= RES_OUT, h1_out);
MT_SA(RES_OUT + sizeof(res_gold) <= MT_BUF_SIZE, out_fits);

static volatile uint8_t *const res_buf = (volatile uint8_t *)(uintptr_t)MT_BUF_BASE;

static void res_stage(uint32_t off, const unsigned char *src, uint32_t n)
{
    uint32_t i;

    for (i = 0; i < n; i++)
    {
        res_buf[off + i] = src[i];
    }
}

static void res_cfg(const unsigned char *cfg, net_layer_t *L, uint32_t skip_off)
{
    uint32_t word = (uint32_t)cfg[0] | ((uint32_t)cfg[1] << 8) |
                    ((uint32_t)cfg[2] << 16) | ((uint32_t)cfg[3] << 24);

    L->mult  = (int16_t)(word & 0xFFFFu);
    L->shift = (uint8_t)((word >> 16) & 0x1Fu);
    L->zp    = (int8_t)((word >> 21) & 0xFFu);
    L->relu  = (uint8_t)((word >> 29) & 0x1u);
    L->nmt   = cfg[4];
    L->skip_off = skip_off;
}

static int mt_res_command(int argc, char **argv)
{
    net_layer_t L1, L2;
    uint32_t cmds = 0u, start, end, i, bad = 0u;
    int rc;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor residual block: 8x8x%d, y = relu(conv2(relu(conv1(x))) + x).\n",
               (int)RES_C);

    res_stage(RES_WT,    res_wt1,   sizeof(res_wt1));
    res_stage(RES_WT2,   res_wt2,   sizeof(res_wt2));
    res_stage(RES_BIAS,  res_bias1, sizeof(res_bias1));
    res_stage(RES_BIAS2, res_bias2, sizeof(res_bias2));
    res_stage(RES_CFG,   res_cfg1,  sizeof(res_cfg1));
    res_stage(RES_CFG2,  res_cfg2,  sizeof(res_cfg2));
    res_stage(RES_IMG,   res_img,   sizeof(res_img));

    L1 = (net_layer_t){RES_H, RES_W, RES_C, RES_C, 3u, 1u, 1u, 0, 0u, 0,
                       RES_IMG, RES_PAD, RES_H1, RES_WT, RES_BIAS, RES_CFG, 0u};
    res_cfg(res_cfg1, &L1, 0u);

    L2 = (net_layer_t){RES_H, RES_W, RES_C, RES_C, 3u, 1u, 0u, 0, 0u, 0,
                       RES_H1, RES_PAD, RES_OUT, RES_WT2, RES_BIAS2, RES_CFG2, 0u};
    res_cfg(res_cfg2, &L2, RES_IMG);
    L2.skip = 2u;    /* ADD8 with the input, then RELU8 */

    rt_kprintf("  conv1 nmt=%u relu=%u | conv2 nmt=%u relu=%u skip=%u\n",
               (unsigned)L1.nmt, (unsigned)L1.relu,
               (unsigned)L2.nmt, (unsigned)L2.relu, (unsigned)L2.skip);

    mt_reset_status();
    start = mt_rd_mcycle();
    JYD_MMIO32(JYD_LED_ADDR) = 1u;

    net_pad(&L1);
    if ((rc = net_conv(&L1, &cmds)) != 0) goto fail;

    for (i = 0; i < RES_OUT_BYTES; i++)
    {
        if (res_buf[RES_H1 + i] != res_gold_h1[i])
        {
            if (bad < 4u)
            {
                rt_kprintf("  conv1[%u]: got %02x expect %02x\n", (unsigned)i,
                           (unsigned)res_buf[RES_H1 + i],
                           (unsigned)res_gold_h1[i]);
            }
            bad++;
        }
    }
    rt_kprintf("  conv1 stage: %u bytes differ\n", (unsigned)bad);
    bad = 0u;

    /* Run conv2 first WITHOUT the residual, so a mismatch can be attributed to
     * the convolution or to the vector unit rather than to their combination. */
    L2.skip = 0u;
    net_pad(&L2);
    if ((rc = net_conv(&L2, &cmds)) != 0) goto fail;

    for (i = 0; i < RES_OUT_BYTES; i++)
    {
        if (res_buf[RES_OUT + i] != res_gold_h2[i])
        {
            if (bad < 4u)
            {
                rt_kprintf("  conv2[%u]: got %02x expect %02x\n", (unsigned)i,
                           (unsigned)res_buf[RES_OUT + i],
                           (unsigned)res_gold_h2[i]);
            }
            bad++;
        }
    }
    rt_kprintf("  conv2 stage (no residual): %u bytes differ\n", (unsigned)bad);
    bad = 0u;

    /* Now with the residual: out = relu(out + x). */
    L2.skip = 2u;
    net_pad(&L2);
    if ((rc = net_conv(&L2, &cmds)) != 0) goto fail;

    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    end = mt_rd_mcycle();



    for (i = 0; i < RES_OUT_BYTES; i++)
    {
        uint8_t got = res_buf[RES_OUT + i];

        if (got != res_gold[i])
        {
            if (bad < 6u)
            {
                rt_kprintf("  byte %u (grp %u h %u w %u c %u): got %02x expect %02x\n",
                           (unsigned)i, (unsigned)(i / (RES_H * RES_W * 4u)),
                           (unsigned)((i / 4u / RES_W) % RES_H),
                           (unsigned)((i / 4u) % RES_W), (unsigned)(i % 4u),
                           (unsigned)got, (unsigned)res_gold[i]);
            }
            bad++;
        }
    }

    if (bad != 0u)
    {
        rt_kprintf("miniTensor residual FAILED: %u/%u bytes differ\n",
                   (unsigned)bad, (unsigned)RES_OUT_BYTES);
        halt(70);
        return -1;
    }

    rt_kprintf("miniTensor residual PASSED (%u/%u bytes, %u commands, %u cycles)\n",
               (unsigned)RES_OUT_BYTES, (unsigned)RES_OUT_BYTES,
               (unsigned)cmds, (unsigned)(end - start));
    return 0;

fail:
    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    rt_kprintf("miniTensor residual FAILED, rc=%d\n", rc);
    halt(71);
    return rc;
}
MSH_CMD_EXPORT_ALIAS(mt_res_command, mt_res, run a residual (skip) block via the VPU.);
