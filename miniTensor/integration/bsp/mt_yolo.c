/*
 * mt_yolo.c -- execute a REAL YOLO convolution on miniTensor.
 *
 * The weights are the stem of tiny-yolov3 (ONNX model zoo), with its
 * BatchNormalization folded in, quantised and packed by pack_real.py.  This is
 * the first network layer in the project whose weights come from a trained
 * model rather than from an LCG or a synthetic task.
 *
 * One deliberate workaround, measured by onnx_feasibility.py: the stem is
 * 3-channel and MT_GEMM needs multiples of 4, so the input is zero-padded to 4
 * channels.
 *
 * The layer's real activation, LeakyReLU(0.1), runs for real.  It needs no new
 * hardware: for 0 < a < 1, leaky(x) = max(x, a*x), the epilogue multiplier is a
 * signed 16-bit field, and the VPU has a signed MAX8.  So the epilogue runs
 * twice over the same C tile -- once with mult, once with round(mult*a) -- and
 * MAX8 combines them.  That costs one extra epilogue and one MAX8 per tile,
 * not a second convolution.
 */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"
#include "mt.h"
#include "mt_net.h"
#include "mt_yolo_weights.h"

#define YOLO_PAD    0x0000u   /* 3*1*34*32*4 = 13056 B -> 0x3300 */
#define YOLO_WT    0x4000u   /*  36 rows    =   576 B -> 0x4240 */
#define YOLO_BIAS    0x4400u   /*  16 rows    =   256 B -> 0x4500 */
#define YOLO_CFG   0x4600u
#define YOLO_IMG    0x4800u   /* 32*32*4     =  4096 B -> 0x5800 */
#define YOLO_OUT    0x5800u   /* 32*32*16    = 16384 B -> 0x9800 */

#define MT_SA(cond, tag) typedef char mt_sa_##tag[(cond) ? 1 : -1]
MT_SA(YOLO_PAD + (3u * (YOLO_CIN / 4u) * ((YOLO_RES + 2u) * YOLO_RES * 4u)) <= YOLO_WT,
      pad_wt);
MT_SA(YOLO_WT + sizeof(yolo_wt) <= YOLO_BIAS, wt_bias);
MT_SA(YOLO_BIAS + sizeof(yolo_bias) <= YOLO_CFG, bias_cfg);
MT_SA(YOLO_CFG + sizeof(yolo_cfg) <= YOLO_IMG, cfg_img);
MT_SA(YOLO_IMG + sizeof(yolo_img) <= YOLO_OUT, img_out);
MT_SA(YOLO_OUT + sizeof(yolo_gold) <= MT_BUF_SIZE, out_fits);

static volatile uint8_t *const yolo_buf = (volatile uint8_t *)(uintptr_t)MT_BUF_BASE;

static void yolo_stage(uint32_t off, const unsigned char *src, uint32_t n)
{
    uint32_t i;

    for (i = 0; i < n; i++)
    {
        yolo_buf[off + i] = src[i];
    }
}

static int mt_yolo_command(int argc, char **argv)
{
    net_layer_t L;
    uint32_t cmds = 0u, start, end, i, bad = 0u, word;
    int rc;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor on a real YOLO layer: tiny-yolov3 stem, "
               "3->%d conv %dx%d, run at %dx%d.\n",
               (int)YOLO_COUT, YOLO_RES, YOLO_RES, YOLO_RES, YOLO_RES);

    yolo_stage(YOLO_WT,   yolo_wt,   sizeof(yolo_wt));
    yolo_stage(YOLO_BIAS, yolo_bias, sizeof(yolo_bias));
    yolo_stage(YOLO_CFG,  yolo_cfg,  sizeof(yolo_cfg));
    yolo_stage(YOLO_IMG,  yolo_img,  sizeof(yolo_img));

    word = (uint32_t)yolo_cfg[0] | ((uint32_t)yolo_cfg[1] << 8) |
           ((uint32_t)yolo_cfg[2] << 16) | ((uint32_t)yolo_cfg[3] << 24);

    L = (net_layer_t){YOLO_RES, YOLO_RES, YOLO_CIN, YOLO_COUT, 3u, 1u, 0u, 0,
                      0u, 0, YOLO_IMG, YOLO_PAD, YOLO_OUT,
                      YOLO_WT, YOLO_BIAS, YOLO_CFG, 0u};
    L.mult  = (int16_t)(word & 0xFFFFu);
    L.shift = (uint8_t)((word >> 16) & 0x1Fu);
    L.zp    = (int8_t)((word >> 21) & 0xFFu);
    L.relu  = (uint8_t)((word >> 29) & 0x1u);
    L.nmt   = yolo_cfg[4];

    L.leaky = 1u;    /* LeakyReLU(0.1) as max(x, a*x) via the second config row */

    rt_kprintf("  channels padded %d->%d for MT_GEMM, nmt=%u, leaky=%u"
               " (real LeakyReLU, done with 2 epilogues + MAX8)\n",
               (int)(YOLO_CIN - 1), (int)YOLO_CIN, (unsigned)L.nmt,
               (unsigned)L.leaky);

    mt_reset_status();
    start = mt_rd_mcycle();
    JYD_MMIO32(JYD_LED_ADDR) = 1u;

    net_pad(&L);
    if ((rc = net_conv(&L, &cmds)) != 0) goto fail;

    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    end = mt_rd_mcycle();

    for (i = 0; i < YOLO_OUT_BYTES; i++)
    {
        uint8_t got = yolo_buf[YOLO_OUT + i];

        if (got != yolo_gold[i])
        {
            if (bad < 4u)
            {
                rt_kprintf("  byte %u: got %02x expect %02x\n", (unsigned)i,
                           (unsigned)got, (unsigned)yolo_gold[i]);
            }
            bad++;
        }
    }

    if (bad != 0u)
    {
        rt_kprintf("miniTensor real YOLO layer FAILED: %u/%u bytes differ\n",
                   (unsigned)bad, (unsigned)YOLO_OUT_BYTES);
        halt(80);
        return -1;
    }

    rt_kprintf("miniTensor real YOLO layer PASSED (%u/%u bytes, %u commands,"
               " %u cycles)\n", (unsigned)YOLO_OUT_BYTES,
               (unsigned)YOLO_OUT_BYTES, (unsigned)cmds,
               (unsigned)(end - start));
    return 0;

fail:
    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    rt_kprintf("miniTensor real YOLO layer FAILED, rc=%d\n", rc);
    halt(81);
    return rc;
}
MSH_CMD_EXPORT_ALIAS(mt_yolo_command, mt_yolo, run a real YOLO convolution.);
