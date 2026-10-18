/*
 * mt_detect.c -- deploy the trained, quantised detector on miniTensor.
 *
 * The weights come from integration/tools/pack_weights.py, which quantises the
 * numpy-trained model to INT8, packs it into the exact memory layout the
 * accelerator consumes, and also computes the integer forward pass that
 * mirrors the RTL.  That integer result ships as \'det_gold\', so this command
 * checks the hardware against the reference bit for bit rather than against a
 * tolerance.
 *
 * One subtlety: .rodata lives in cacheable DRAM, and the accelerator's DMA
 * reads physical memory directly.  Weights therefore have to be *staged* into
 * the uncached scratch window before the first MT_LOAD can see them.
 */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"
#include "mt.h"
#include "mt_net.h"
#include "mt_detect_weights.h"

#define DET_IMG_BYTES   (32u * 32u * 4u)
#define DET_OUT_BYTES   (8u * 8u * 8u)

/* Packed sizes produced by pack_weights.py. */
#define DET_WT_OFF_L1   0x0000u
#define DET_WT_OFF_L2   0x0120u
#define DET_WT_OFF_L3   0x05A0u
#define DET_WT_OFF_L4   0x0EA0u
#define DET_BIAS_OFF_L1 0x000u
#define DET_BIAS_OFF_L2 0x080u
#define DET_BIAS_OFF_L3 0x180u
#define DET_BIAS_OFF_L4 0x280u
#define DET_CFG_OFF_L1  0x00u
#define DET_CFG_OFF_L2  0x10u
#define DET_CFG_OFF_L3  0x20u
#define DET_CFG_OFF_L4  0x30u

static volatile uint8_t *const det_buf = (volatile uint8_t *)(uintptr_t)MT_BUF_BASE;

static void det_copy_to_scratch(uint32_t off, const unsigned char *src, uint32_t n)
{
    uint32_t i;

    for (i = 0; i < n; i++)
    {
        det_buf[off + i] = src[i];
    }
}

static uint8_t det_rd8(uint32_t off) { return det_buf[off]; }

/* The epilogue config word is the single source of truth for the requant
 * factors, so read them back out of the packed image instead of duplicating
 * the numbers here. */
static void det_cfg_from(const unsigned char *cfg, net_layer_t *L)
{
    uint32_t word = (uint32_t)cfg[0] | ((uint32_t)cfg[1] << 8) |
                    ((uint32_t)cfg[2] << 16) | ((uint32_t)cfg[3] << 24);

    L->mult  = (int16_t)(word & 0xFFFFu);
    L->shift = (uint8_t)((word >> 16) & 0x1Fu);
    L->zp    = (int8_t)((word >> 21) & 0xFFu);
    L->relu  = (uint8_t)((word >> 29) & 0x1u);
    L->nmt   = cfg[4];   /* weight tile size chosen by the packer */
}

/* Compare the first 16 bytes of a stage against the Python trace, so a
 * mismatch can be attributed to a specific layer. */
static int det_probe_check(uint32_t idx, uint32_t off, const char *name,
                           uint32_t img)
{
    uint32_t i;
    int bad = 0;

    for (i = 0; i < 16u; i++)
    {
        uint8_t got = det_rd8(off + i);
        uint8_t exp = det_probe[(idx * 16u) + i];

        if (got != exp)
        {
            if (bad < 2)
            {
                rt_kprintf("  img %u probe %s byte %u: got %02x expect %02x\n",
                           (unsigned)img, name, (unsigned)i,
                           (unsigned)got, (unsigned)exp);
            }
            bad++;
        }
    }
    return bad;
}

static void det_make_layers(net_layer_t *L)
{
    L[0] = (net_layer_t){32u, 32u, 4u, 8u, 3u, 1u, 1u, 0, 0u, 0,
                         NET_IMAGE, PAD_BUF, OUT_BUF,
                         NET_WT + DET_WT_OFF_L1, NET_BIAS + DET_BIAS_OFF_L1,
                         NET_CFG + DET_CFG_OFF_L1};
    L[1] = (net_layer_t){16u, 16u, 8u, 16u, 3u, 1u, 1u, 0, 0u, 0,
                         MID_BUF, PAD_BUF, OUT_BUF,
                         NET_WT + DET_WT_OFF_L2, NET_BIAS + DET_BIAS_OFF_L2,
                         NET_CFG + DET_CFG_OFF_L2};
    L[2] = (net_layer_t){8u, 8u, 16u, 16u, 3u, 1u, 1u, 0, 0u, 0,
                         MID_BUF, PAD_BUF, OUT_BUF,
                         NET_WT + DET_WT_OFF_L3, NET_BIAS + DET_BIAS_OFF_L3,
                         NET_CFG + DET_CFG_OFF_L3};
    L[3] = (net_layer_t){8u, 8u, 16u, 8u, 1u, 0u, 0u, 0, 0u, 0,
                         OUT_BUF, PAD_BUF, MID_BUF,
                         NET_WT + DET_WT_OFF_L4, NET_BIAS + DET_BIAS_OFF_L4,
                         NET_CFG + DET_CFG_OFF_L4};

    det_cfg_from(det_cfg1, &L[0]);
    det_cfg_from(det_cfg2, &L[1]);
    det_cfg_from(det_cfg3, &L[2]);
    det_cfg_from(det_cfg4, &L[3]);
}

static int mt_detect_command(int argc, char **argv)
{
    net_layer_t L[4];
    uint32_t cmds = 0u, start, end, i, img;
    int rc, bad = 0, images_ok = 0;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor detector: packed INT8 weights, %d test images.\n",
               (int)DET_IMG_COUNT);

    det_make_layers(L);

    /* Stage the packed image into the uncached scratch so the DMA can read it. */
    det_copy_to_scratch(NET_WT + DET_WT_OFF_L1, det_wt1,   sizeof(det_wt1));
    det_copy_to_scratch(NET_WT + DET_WT_OFF_L2, det_wt2,   sizeof(det_wt2));
    det_copy_to_scratch(NET_WT + DET_WT_OFF_L3, det_wt3,   sizeof(det_wt3));
    det_copy_to_scratch(NET_WT + DET_WT_OFF_L4, det_wt4,   sizeof(det_wt4));
    det_copy_to_scratch(NET_BIAS + DET_BIAS_OFF_L1, det_bias1, sizeof(det_bias1));
    det_copy_to_scratch(NET_BIAS + DET_BIAS_OFF_L2, det_bias2, sizeof(det_bias2));
    det_copy_to_scratch(NET_BIAS + DET_BIAS_OFF_L3, det_bias3, sizeof(det_bias3));
    det_copy_to_scratch(NET_BIAS + DET_BIAS_OFF_L4, det_bias4, sizeof(det_bias4));
    det_copy_to_scratch(NET_CFG + DET_CFG_OFF_L1, det_cfg1, sizeof(det_cfg1));
    det_copy_to_scratch(NET_CFG + DET_CFG_OFF_L2, det_cfg2, sizeof(det_cfg2));
    det_copy_to_scratch(NET_CFG + DET_CFG_OFF_L3, det_cfg3, sizeof(det_cfg3));
    det_copy_to_scratch(NET_CFG + DET_CFG_OFF_L4, det_cfg4, sizeof(det_cfg4));

    rt_kprintf("  L1 mult=%d shift=%u relu=%u\n", (int)L[0].mult,
               (unsigned)L[0].shift, (unsigned)L[0].relu);
    rt_kprintf("  L4 mult=%d shift=%u relu=%u\n", (int)L[3].mult,
               (unsigned)L[3].shift, (unsigned)L[3].relu);

    mt_reset_status();
    start = mt_rd_mcycle();
    JYD_MMIO32(JYD_LED_ADDR) = 1u;

    for (img = 0; img < DET_IMG_COUNT; img++)
    {
        det_copy_to_scratch(NET_IMAGE, &det_imgs[img * DET_IMG_BYTES],
                            DET_IMG_BYTES);

        net_pad(&L[0]);
        if ((rc = net_conv(&L[0], &cmds)) != 0) goto fail;
        if (img == 0u) { (void)det_probe_check(0u, OUT_BUF, "L1", img); }
        net_pool2(MT_BUF_BASE, OUT_BUF, MID_BUF, 2u, 32u, 32u, 0u, 0u);
        if (img == 0u) { (void)det_probe_check(1u, MID_BUF, "P1", img); }

        net_pad(&L[1]);
        if ((rc = net_conv(&L[1], &cmds)) != 0) goto fail;
        if (img == 0u) { (void)det_probe_check(2u, OUT_BUF, "L2", img); }
        net_pool2(MT_BUF_BASE, OUT_BUF, MID_BUF, 4u, 16u, 16u, 0u, 0u);
        if (img == 0u) { (void)det_probe_check(3u, MID_BUF, "P2", img); }

        net_pad(&L[2]);
        if ((rc = net_conv(&L[2], &cmds)) != 0) goto fail;
        if (img == 0u) { (void)det_probe_check(4u, OUT_BUF, "L3", img); }

        net_pad(&L[3]);
        if ((rc = net_conv(&L[3], &cmds)) != 0) goto fail;
        if (img == 0u) { (void)det_probe_check(5u, MID_BUF, "L4", img); }

        /* Compare the head output against the Python integer golden. */
        for (i = 0; i < DET_OUT_BYTES; i++)
        {
            uint8_t got = det_rd8(MID_BUF + i);

            if (got != det_gold[(img * DET_OUT_BYTES) + i])
            {
                if (bad < 4)
                {
                    rt_kprintf("  img %u byte %u: got %02x expect %02x\n",
                               (unsigned)img, (unsigned)i,
                               (unsigned)got,
                               (unsigned)det_gold[(img * DET_OUT_BYTES) + i]);
                }
                bad++;
            }
        }
        if (bad == 0)
        {
            /* Decode: weighted centroid of the objectness map (channel 0 of
             * group 0 lives at byte (h*8+w)*4). */
            int32_t sum = 0, sy = 0, sx = 0, gy, gx;

            for (gy = 0; gy < 8; gy++)
            {
                for (gx = 0; gx < 8; gx++)
                {
                    int32_t v = (int8_t)det_rd8(MID_BUF + (((uint32_t)gy * 8u +
                                                            (uint32_t)gx) * 4u));

                    if (v > 0)
                    {
                        sum += v;
                        sy += v * gy;
                        sx += v * gx;
                    }
                }
            }
            if (sum > 0)
            {
                rt_kprintf("  img %u: detection centre cell (%d.%d, %d.%d)"
                           " -> pixel (%d, %d)\n",
                           (unsigned)img, (int)(sy / sum), (int)((sy * 10 / sum) % 10),
                           (int)(sx / sum), (int)((sx * 10 / sum) % 10),
                           (int)((sx * 10 / sum) / 10 * 4 + 2),
                           (int)((sy * 10 / sum) / 10 * 4 + 2));
            }
            images_ok++;
        }
        else
        {
            break;   /* stop at the first image that disagrees */
        }
    }

    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    end = mt_rd_mcycle();

    if (bad != 0)
    {
        rt_kprintf("miniTensor detector FAILED: %d bytes differ from the"
                   " Python golden\n", bad);
        halt(50);
    }

    rt_kprintf("miniTensor detector PASSED: %d/%d images, %u commands,"
               " %u cycles\n", images_ok, (int)DET_IMG_COUNT,
               (unsigned)(cmds / DET_IMG_COUNT), (unsigned)(end - start));
    return 0;

fail:
    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    rt_kprintf("miniTensor detector FAILED at layer, rc=%d\n", rc);
    halt(51);
    return rc;
}
MSH_CMD_EXPORT_ALIAS(mt_detect_command, mt_detect, run the packed-weight detector.);
