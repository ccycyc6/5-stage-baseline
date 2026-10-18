/*
 * mt_yolocnn.c -- a multi-layer slice of a REAL YOLO model on miniTensor.
 *
 * Runs the first three stages of the tiny-yolov3 backbone with the model's real
 * trained weights (BatchNormalization folded) and its real LeakyReLU(0.1):
 *
 *     x -> conv3x3(3->16)+leaky -> pool -> conv3x3(16->32)+leaky
 *       -> pool -> conv3x3(32->64)+leaky
 *
 * Each stage is checked against its own golden, so a mismatch is attributable
 * to one layer rather than to the chain.  Convolutions #1 and #2 need more
 * weight rows than UB_WT holds (288 and 1152 vs 144), so this also exercises
 * net_conv's weight tiling on a real model rather than on a synthetic one.
 */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"
#include "mt.h"
#include "mt_net.h"
#include "mt_yolocnn_weights.h"

/* Scratch layout inside the 64 KiB uncached alias.  The compile-time asserts
 * below keep every block clear of the next one. */
#if YC_RES0 == 16
#define YC_PAD    0x0000u   /* max 3*4*10*8*4 = 3840 B -> 0x0F00 */
#define YC_WT    0x1000u   /* 36+288+1152 rows        -> 0x6C40 */
#define YC_BIAS    0x7000u   /* 16+32+64 rows           -> 0x7700 */
#define YC_CFG    0x7800u   /* 3 x 32 B                -> 0x7860 */
#define YC_IMG    0x8000u   /* 16*16*4   = 1024 B      -> 0x8400 */
#define YC_A1    0x8400u   /* 16*16*16  = 4096 B      -> 0x9400 */
#define YC_P1    0x9400u   /*  8*8*16   = 1024 B      -> 0x9800 */
#define YC_A2    0x9800u   /*  8*8*32   = 2048 B      -> 0xA000 */
#define YC_P2    0xA000u   /*  4*4*32   =  512 B      -> 0xA200 */
#define YC_A3    0xA400u   /*  4*4*64   = 1024 B      -> 0xA800 */
#else
#define YC_PAD    0x0000u   /* max 3*4*14*12*4 = 8064 B -> 0x2000 */
#define YC_WT    0x2000u   /* 36+288+1152 rows        -> 0x7C40 */
#define YC_BIAS    0x8000u   /* 16+32+64 rows           -> 0x8700 */
#define YC_CFG    0x8800u   /* 3 x 32 B                -> 0x8860 */
#define YC_IMG    0x9000u   /* 24*24*4   = 2304 B      -> 0x9900 */
#define YC_A1    0x9A00u   /* 24*24*16  = 9216 B      -> 0xBE00 */
#define YC_P1    0xC000u   /* 12*12*16  = 2304 B      -> 0xC900 */
#define YC_A2    0xD000u   /* 12*12*32  = 4608 B      -> 0xE200 */
#define YC_P2    0xE400u   /*  6*8*32   = 1536 B      -> 0xEA00 */
#define YC_A3    0xF000u   /*  6*8*64   = 3072 B      -> 0xFC00 */
#endif

/* Row strides YC_WP0/1/2 come from the generated header: the pool outputs
 * RES0/2 and RES0/4 rounded up to a multiple of 4 for net_conv's 4-pixel tiles
 * (6 -> 8 at RES0 = 24). */

#define YC_WT_1   (YC_WT + 0x240u)
#define YC_WT_2   (YC_WT + 0x1440u)
#define YC_BIAS_1 (YC_BIAS + 0x100u)
#define YC_BIAS_2 (YC_BIAS + 0x300u)
#define YC_CFG_1  (YC_CFG + 0x20u)
#define YC_CFG_2  (YC_CFG + 0x40u)

#define MT_SA(cond, tag) typedef char mt_sa_##tag[(cond) ? 1 : -1]
MT_SA(YC_PAD + (3u * 4u * ((YC_RES0 / 2u) + 2u) * (YC_RES0 / 2u) * 4u) <= YC_WT, pad_wt);
MT_SA(YC_WT + YC_WT_LEN0 + YC_WT_LEN1 + YC_WT_LEN2 <= YC_BIAS, wt_bias);
MT_SA(YC_BIAS + YC_BIAS_LEN0 + YC_BIAS_LEN1 + YC_BIAS_LEN2 <= YC_CFG, bias_cfg);
MT_SA(YC_CFG + YC_CFG_LEN0 + YC_CFG_LEN1 + YC_CFG_LEN2 <= YC_IMG, cfg_img);
MT_SA(YC_IMG + sizeof(yc_img) <= YC_A1, img_a1);
MT_SA(YC_A1 + sizeof(yc_gold0) <= YC_P1, a1_p1);
MT_SA(YC_P1 + (YC_RES1 * YC_WP1 * YC_COUT0) <= YC_A2, p1_a2);
MT_SA(YC_A2 + sizeof(yc_gold1) <= YC_P2, a2_p2);
MT_SA(YC_P2 + (YC_RES2 * YC_WP2 * YC_COUT1) <= YC_A3, p2_a3);
MT_SA(YC_A3 + sizeof(yc_gold2) <= MT_BUF_SIZE, a3_fits);

/* Where this test's buffers live.  Layer offsets stay relative to a base, so
 * pointing YC_BASE at the uncached extension window moves the WHOLE chain --
 * activations, weights and padding -- out of the 64 KiB scratch.  That is the
 * capability the full model needs: tiny-yolov3's stem alone produces 256 KiB at
 * 128x128.  (Set YC_BASE to MT_BUF_BASE to run the identical test in scratch.) */
/* NOTE: bit 21 is NOT decoded by the DMA -- that is exactly how the
 * uncached scratch alias 0x8033_0000 reaches 0x8013_0000 -- so two
 * buffers 2 MiB apart alias for the accelerator.  This base therefore
 * sits above the model blob AND keeps bit 21 clear; choosing
 * 0x80E0_0000 here silently aliased onto the model region at
 * 0x80C0_0000 and corrupted both tests. */
#define YC_BASE   0x80D80000u

static inline volatile uint8_t *yc_at(uint32_t off)
{
    return (volatile uint8_t *)(uintptr_t)(YC_BASE + off);
}

static void yc_stage(uint32_t off, const unsigned char *src, uint32_t n)
{
    uint32_t i;

    for (i = 0; i < n; i++)
    {
        yc_at(off)[i] = src[i];
    }
}

/* Copy a layer's weights out of the blob in the uncached extension window.
 * Both ends are uncached, so this is a plain byte copy and the accelerator's
 * DMA sees the result without any cache maintenance. */
static void yc_stage_blob(uint32_t off, uint32_t blob_off, uint32_t n)
{
    volatile const uint8_t *src =
        (volatile const uint8_t *)(uintptr_t)(YC_BLOB_BASE + blob_off);
    uint32_t i;

    for (i = 0; i < n; i++)
    {
        yc_at(off)[i] = src[i];
    }
}

/* Reads the config row out of the SCRATCH copy, not .rodata: the configs are
 * part of the weight blob now. */
static void yc_setcfg(net_layer_t *L, uint32_t cfg_off)
{
    uint32_t word = (uint32_t)yc_at(cfg_off)[0] |
                    ((uint32_t)yc_at(cfg_off)[1] << 8) |
                    ((uint32_t)yc_at(cfg_off)[2] << 16) |
                    ((uint32_t)yc_at(cfg_off)[3] << 24);

    L->mult  = (int16_t)(word & 0xFFFFu);
    L->shift = (uint8_t)((word >> 16) & 0x1Fu);
    L->zp    = (int8_t)((word >> 21) & 0xFFu);
    L->relu  = (uint8_t)((word >> 29) & 0x1u);
    L->nmt   = yc_at(cfg_off)[4];
    L->leaky = 1u;
}

static int yc_check(const char *name, uint32_t off, const unsigned char *gold,
                    uint32_t n, uint32_t *cmds, uint32_t *cyc)
{
    uint32_t i, bad = 0u, t0, t1;

    t0 = mt_rd_mcycle();
    for (i = 0; i < n; i++)
    {
        if (yc_at(off)[i] != gold[i])
        {
            if (bad < 8u) {
                rt_kprintf("  %s[%u] g%u r%u c%u ch%u: got %02x expect %02x\n",
                           name, (unsigned)i,
                           (unsigned)(i / ((uint32_t)YC_RES0 * YC_RES0 * 4u)),
                           (unsigned)((i / 4u / YC_RES0) % YC_RES0),
                           (unsigned)((i / 4u) % YC_RES0), (unsigned)(i % 4u),
                           (unsigned)yc_at(off)[i], (unsigned)gold[i]);
            }
            bad++;
        }
    }
    t1 = mt_rd_mcycle();
    (void)cmds;
    (void)cyc;
    rt_kprintf("  %-7s %6u bytes  %s", name, (unsigned)n,
               bad ? "MISMATCH" : "ok");
    if (bad) { rt_kprintf(" (%u bytes)", (unsigned)bad); }
    rt_kprintf("\n");
    return (int)bad;
}

static int mt_yolocnn_command(int argc, char **argv)
{
    net_layer_t L;
    uint32_t cmds, total_cmds = 0u, start, end;
    int rc, bad = 0;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor real YOLO backbone slice: convs #0,#1,#2 of"
               " tiny-yolov3, %dx%d input.\n", YC_RES0, YC_RES0);

    /* Weights come from the blob, not from .rodata. */
    rt_kprintf("  weight blob at 0x%08x, %u bytes staged from the uncached window\n",
               (unsigned)YC_BLOB_BASE,
               (unsigned)(YC_WT_LEN0 + YC_WT_LEN1 + YC_WT_LEN2 +
                          YC_BIAS_LEN0 + YC_BIAS_LEN1 + YC_BIAS_LEN2 +
                          YC_CFG_LEN0 + YC_CFG_LEN1 + YC_CFG_LEN2));

    yc_stage_blob(YC_WT,   YC_BLOB_WT0,   YC_WT_LEN0);
    yc_stage_blob(YC_WT_1, YC_BLOB_WT1,   YC_WT_LEN1);
    yc_stage_blob(YC_WT_2, YC_BLOB_WT2,   YC_WT_LEN2);
    yc_stage_blob(YC_BIAS,   YC_BLOB_BIAS0, YC_BIAS_LEN0);
    yc_stage_blob(YC_BIAS_1, YC_BLOB_BIAS1, YC_BIAS_LEN1);
    yc_stage_blob(YC_BIAS_2, YC_BLOB_BIAS2, YC_BIAS_LEN2);
    yc_stage_blob(YC_CFG,   YC_BLOB_CFG0, YC_CFG_LEN0);
    yc_stage_blob(YC_CFG_1, YC_BLOB_CFG1, YC_CFG_LEN1);
    yc_stage_blob(YC_CFG_2, YC_BLOB_CFG2, YC_CFG_LEN2);
    yc_stage(YC_IMG,   yc_img,   sizeof(yc_img));

    mt_reset_status();
    start = mt_rd_mcycle();
    JYD_MMIO32(JYD_LED_ADDR) = 1u;

    /* ---- stage 0: 3->16 at 24x24 ---- */
    L = (net_layer_t){YC_RES0, YC_RES0, 4u, YC_COUT0, 3u, 1u, 0u, 0, 0u, 0,
                      YC_IMG, YC_PAD, YC_A1, YC_WT, YC_BIAS, YC_CFG, 0u};
    yc_setcfg(&L, YC_CFG);
    L.src_w = 0u;              /* the image is already YC_WP0 wide */
    L.wpad  = YC_WP0;
    L.base  = YC_BASE;
    /* Run conv0 WITHOUT the activation first: if that matches, the convolution
     * arithmetic is fine and any remaining error is in the LeakyReLU path. */
    L.leaky = 0u;
    cmds = 0u;
    net_pad(&L);
    if ((rc = net_conv(&L, &cmds)) != 0) goto fail;
    bad += yc_check("conv0p", YC_A1, yc_gold0_plain, sizeof(yc_gold0_plain),
                    &cmds, 0);

    L.leaky = 1u;
    cmds = 0u;
    net_pad(&L);
    if ((rc = net_conv(&L, &cmds)) != 0) goto fail;
    total_cmds += cmds;
    bad += yc_check("conv0", YC_A1, yc_gold0, sizeof(yc_gold0), &cmds, 0);

    net_pool2(YC_BASE, YC_A1, YC_P1, YC_COUT0 / 4u, YC_RES0, YC_RES0, 0u, YC_WP1);

    /* ---- stage 1: 16->32 at 12x12 ---- */
    L = (net_layer_t){YC_RES1, YC_RES1, YC_COUT0, YC_COUT1, 3u, 1u, 0u, 0, 0u, 0,
                      YC_P1, YC_PAD, YC_A2, YC_WT_1, YC_BIAS_1, YC_CFG_1, 0u};
    yc_setcfg(&L, YC_CFG_1);
    L.src_w = YC_WP1;          /* the pooled buffer's row stride */
    L.wpad  = YC_WP1;
    L.base  = YC_BASE;
    cmds = 0u;
    net_pad(&L);
    if ((rc = net_conv(&L, &cmds)) != 0) goto fail;
    total_cmds += cmds;
    bad += yc_check("conv1", YC_A2, yc_gold1, sizeof(yc_gold1), &cmds, 0);

    net_pool2(YC_BASE, YC_A2, YC_P2, YC_COUT1 / 4u, YC_RES1, YC_RES1, YC_WP1, YC_WP2);

    /* ---- stage 2: 32->64 at 6x6 ---- */
    L = (net_layer_t){YC_RES2, YC_RES2, YC_COUT1, YC_COUT2, 3u, 1u, 0u, 0, 0u, 0,
                      YC_P2, YC_PAD, YC_A3, YC_WT_2, YC_BIAS_2, YC_CFG_2, 0u};
    yc_setcfg(&L, YC_CFG_2);
    L.src_w = YC_WP2;
    L.wpad  = YC_WP2;
    L.base  = YC_BASE;          /* 6 logical columns, computed as 8 */
    cmds = 0u;
    net_pad(&L);
    if ((rc = net_conv(&L, &cmds)) != 0) goto fail;
    total_cmds += cmds;
    bad += yc_check("conv2", YC_A3, yc_gold2, sizeof(yc_gold2), &cmds, 0);

    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    end = mt_rd_mcycle();

    if (bad != 0)
    {
        /* KNOWN OPEN.  Every convolution in the chain comes out wrong, and the
         * signature is precise: within each 16-byte A row only the FIRST pixel
         * is correct (bytes 0..3 match, 4..15 do not, and the wrong values
         * repeat across pixels).  The same stem layer passes bit-exactly in
         * mt_yolo at 32x32, so the difference is the 24x24 geometry -- ntiles
         * is 6 here versus 8 there.  Ruled out so far: the LeakyReLU path (the
         * no-activation golden fails identically), the weight tiling, and the
         * scratch layout (the compile-time asserts pass).  Deliberately not
         * fatal so it stays as a reproducer and the rest of the regression
         * still runs.  See handoff/y11_chain_bug.md. */
        rt_kprintf("miniTensor real YOLO chain FAILED: %d bytes differ"
                   " (KNOWN OPEN -- see handoff/y11_chain_bug.md)\n", bad);
        return -1;
    }

    rt_kprintf("miniTensor real YOLO chain PASSED (3 real convs + 2 pools,"
               " %u commands, %u cycles)\n", (unsigned)total_cmds,
               (unsigned)(end - start));
    return 0;

fail:
    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    rt_kprintf("miniTensor real YOLO chain FAILED, rc=%d\n", rc);
    halt(91);
    return rc;
}
MSH_CMD_EXPORT_ALIAS(mt_yolocnn_command, mt_yolocnn, run 3 real YOLO conv layers.);
