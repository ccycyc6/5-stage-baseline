/*
 * mt_yolomodel.c -- the COMPLETE tiny-yolov3 deployed on miniTensor.
 *
 * This is the end of the road the Y1..Y18 rounds were walking: not a slice of
 * the backbone but the whole graph, every convolution, every pool, the FPN
 * upsample and the channel concat, driven by the table emitted by
 * integration/tools/pack_full.py.
 *
 *     conv3x3 3->16   -> pool2/2 -> conv3x3 16->32   -> pool2/2
 *     conv3x3 32->64  -> pool2/2 -> conv3x3 64->128  -> pool2/2
 *     conv3x3 128->256-> pool2/2 -> conv3x3 256->512 -> pool2/1(SAME)
 *     conv3x3 512->1024 -> conv1x1 1024->256
 *         |-> conv1x1 256->128 -> upsample x2 --> concat(.,128->256)
 *         |-> conv3x3 256->512 -> head1 1x1 512->255
 *         \-> conv3x3 384->256 -> head2 1x1 256->255
 *
 * The layers' real trained weights (BatchNormalization folded), its real
 * LeakyReLU(0.1), and the real route/upsample structure all execute on the
 * accelerator.  Every stage is checked byte for byte against the integer
 * golden packed next to the weights.
 *
 * Everything -- weights, input, activations, padding scratch and goldens --
 * is addressed relative to ONE base, supplied by the linker as __model_start.
 * The blob therefore lives wherever the linker puts it (the 12 MiB uncached
 * window) without this file knowing its address.
 *
 * Note the padded 2x2 stride-1 pool (ONNX SAME_UPPER): the old net_pool_k
 * shrank the map by one, which is what tiny-yolov3's layer 11 would do with
 * pads=0.  The real graph keeps the extent, and without that the upsample and
 * route sizes cannot line up.
 */
#include <rtthread.h>
#include <finsh.h>
#include <stdint.h>

#include "board.h"
#include "mt.h"
#include "mt_net.h"
#include "mt_yolomodel_weights.h"

extern char __model_start[];
#define YM_BASE   ((uint32_t)(uintptr_t)__model_start)
#define YM_PAD    (YM_SCRATCH + YM_PAD_OFF)

static inline volatile uint8_t *ym_at(uint32_t off)
{
    return (volatile uint8_t *)(uintptr_t)(YM_BASE + off);
}

static int mt_yolomodel_command(int argc, char **argv)
{
    uint32_t i, cmds = 0u, start, end;
    int bad_total = 0;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor FULL tiny-yolov3: %u stages from 0x%08x.\n",
               (unsigned)YM_LAYERS, (unsigned)YM_BASE);

    mt_reset_status();
    start = mt_rd_mcycle();
    JYD_MMIO32(JYD_LED_ADDR) = 1u;

    for (i = 0; i < YM_LAYERS; i++)
    {
        const ym_layer_t *T = &ym_layers[i];
        uint32_t j, bad = 0u, t0, t1;
        int rc = 0;

        t0 = mt_rd_mcycle();

        if (T->kind == 0u)
        {
            net_layer_t L;

            L.h = T->h;            L.w = T->w;
            L.c_in = T->cin;       L.c_out = T->cout;
            L.k = T->k;            L.pad = T->pad;
            L.relu = 0u;           L.mult = 0;    L.shift = 0u;  L.zp = 0;
            L.src_off = T->src;    L.pad_off = YM_PAD;  L.out_off = T->out;
            L.wt_off = T->wt;      L.bias_off = T->bias; L.cfg_off = T->cfg;
            /* nmt is written into the packed config row by the packer, so the
             * firmware and the golden cannot disagree about the tiling. */
            L.nmt = ym_at(T->cfg)[4];
            L.skip_off = 0u;       L.skip = 0u;
            L.leaky = T->leaky;
            L.src_w = T->src_w;    L.wpad = T->wpad;
            L.base = YM_BASE;

            net_pad(&L);
            rc = net_conv(&L, &cmds);
        }
        else if (T->kind == 1u)
        {
            net_pool2(YM_BASE, T->src, T->out, T->cin / 4u, T->h, T->w,
                      T->src_w, T->wpad);
        }
        else if (T->kind == 2u)
        {
            net_pool_k_same(YM_BASE, T->src, T->out, T->cin / 4u, T->h, T->w,
                            2u, 1u, T->src_w, T->wpad);
        }
        else if (T->kind == 3u)
        {
            net_upsample2(YM_BASE, T->src, T->out, T->cin / 4u, T->h, T->w,
                          T->src_w, T->wpad);
        }
        else
        {
            net_concat2(YM_BASE, T->out, T->src, T->cin / 4u,
                        T->src2, T->cout / 4u, T->h, T->w);
        }

        t1 = mt_rd_mcycle();

        if (rc != 0)
        {
            JYD_MMIO32(JYD_LED_ADDR) = 0u;
            rt_kprintf("  stage %u FAILED, rc=%d\n", (unsigned)i, rc);
            halt(100);
            return rc;
        }

        for (j = 0; j < T->glen; j++)
        {
            if (ym_at(T->out)[j] != ym_at(T->gold)[j])
            {
                if (bad < 3u)
                {
                    rt_kprintf("  stage %u byte %u: got %02x expect %02x\n",
                               (unsigned)i, (unsigned)j,
                               (unsigned)ym_at(T->out)[j],
                               (unsigned)ym_at(T->gold)[j]);
                }
                bad++;
            }
        }
        bad_total += (int)bad;
        rt_kprintf("  %2u %-4s %2ux%-2u %4u->%-4u %6u B  %s  (%u cycles)\n",
                   (unsigned)i,
                   T->kind == 0u ? "conv" : (T->kind == 1u ? "pool" :
                   (T->kind == 2u ? "pls1" : (T->kind == 3u ? "up" : "cat"))),
                   (unsigned)T->h, (unsigned)T->w, (unsigned)T->cin,
                   (unsigned)T->cout, (unsigned)T->glen,
                   bad ? "MISMATCH" : "ok", (unsigned)(t1 - t0));
    }

    JYD_MMIO32(JYD_LED_ADDR) = 0u;
    end = mt_rd_mcycle();

    if (bad_total != 0)
    {
        rt_kprintf("miniTensor FULL model FAILED: %d bytes differ\n", bad_total);
        halt(101);
        return -1;
    }

    rt_kprintf("miniTensor FULL tiny-yolov3 PASSED (%u stages, %u commands,"
               " %u cycles)\n", (unsigned)YM_LAYERS, (unsigned)cmds,
               (unsigned)(end - start));
    return 0;
}
MSH_CMD_EXPORT_ALIAS(mt_yolomodel_command, mt_yolomodel,
                     run the complete tiny-yolov3.);
