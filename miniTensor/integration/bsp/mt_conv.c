/*
 * mt_conv.c -- one real 3x3 convolution layer on the miniTensor tile engine.
 *
 * This is the first non-trivial CNN-shaped workload: it proves the accelerator
 * can do a real convolution, not just a single hand-fed GEMM.
 *
 * Problem shape (chosen to fit the 256-row UB):
 *
 *   input   6x6x4  (NHWC, INT8, zero padded)
 *   conv    3x3, stride 1, pad 1, 4 output channels
 *   output  6x6x4  (INT8, requantised)
 *   M = 4 out-channels, N = 36 output positions, K = 4*9 = 36
 *
 * Mapping onto the only primitive miniTensor has (C[i][j] = sum_k A[i][k]*B[k][j],
 * a 4x4x4 INT8 tile with A and B in one UB row each):
 *
 *   A = weights   (M x K)  ->  (M/4) * (K/4) = 1 * 9   =  9 UB rows
 *   B = im2col    (K x N)  ->  (K/4) * (N/4) = 9 * 9   = 81 UB rows
 *   C             (M x N)  ->  (N/4) * 4     = 9 * 4   = 36 UB rows
 *
 * The CPU builds the im2col matrix and the packed weight rows, the DMA pulls
 * them into the UB once, and the GEMM loop then runs entirely inside the
 * accelerator with no further bus traffic.
 *
 * The exact same layout is checked host-side by
 * integration/tools/conv_layout_check.py before it is ever run on RTL.
 */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"
#include "mt.h"

#define CONV_C_IN   4u
#define CONV_C_OUT  4u
#define CONV_H      6u
#define CONV_W      6u
#define CONV_K      (CONV_C_IN * 9u)          /* 36 */
#define CONV_N      (CONV_H * CONV_W)         /* 36 */
#define CONV_KS     (CONV_K / 4u)             /* 9  */
#define CONV_NT     (CONV_N / 4u)             /* 9  */

/* Scratch-buffer offsets inside the 64 KiB uncached window. */
#define CONV_W_OFF    0x1000u
#define CONV_B_OFF    0x2000u
#define CONV_BIAS_OFF 0x3000u
#define CONV_CFG_OFF  0x3100u
#define CONV_OUT_OFF  0x3200u

/* UB row allocation: 9 + 81 + 36 + 4 + 1 + 9 = 140 of 256 rows. */
#define CONV_UB_A     0u
#define CONV_UB_B     16u
#define CONV_UB_C     104u
#define CONV_UB_BIAS  144u
#define CONV_UB_CFG   148u
#define CONV_UB_OUT   152u

#define CONV_MULT   16
#define CONV_SHIFT  10
#define CONV_ZP     0
#define CONV_RELU   0

static volatile uint8_t *const conv_buf = (volatile uint8_t *)(uintptr_t)MT_BUF_BASE;

static void conv_wr8(uint32_t off, uint8_t value)  { conv_buf[off] = value; }
static uint8_t conv_rd8(uint32_t off)              { return conv_buf[off]; }
static void conv_wr32(uint32_t off, uint32_t value)
{
    *(volatile uint32_t *)(uintptr_t)(MT_BUF_BASE + off) = value;
}

static int8_t  conv_x[CONV_H * CONV_W * CONV_C_IN];
static int8_t  conv_w[CONV_C_OUT * CONV_K];
static int32_t conv_bias[CONV_C_OUT];
static uint8_t conv_gold[CONV_NT * 16u];

static uint32_t conv_lcg = 0x2468ACE0u;

static uint32_t conv_rand(void)
{
    conv_lcg = (conv_lcg * 1103515245u) + 12345u;
    return conv_lcg;
}

static int8_t conv_input_at(uint32_t k, uint32_t n)
{
    uint32_t c  = k / 9u;
    uint32_t ky = (k % 9u) / 3u;
    uint32_t kx = k % 3u;
    uint32_t ho = n / CONV_W;
    uint32_t wo = n % CONV_W;
    int32_t  hi = (int32_t)ho + (int32_t)ky - 1;
    int32_t  wi = (int32_t)wo + (int32_t)kx - 1;

    if (hi < 0 || hi >= (int32_t)CONV_H || wi < 0 || wi >= (int32_t)CONV_W)
    {
        return 0;
    }
    return conv_x[((uint32_t)hi * CONV_W + (uint32_t)wi) * CONV_C_IN + c];
}

static void conv_build_inputs(void)
{
    uint32_t i;

    for (i = 0; i < CONV_H * CONV_W * CONV_C_IN; i++)
    {
        conv_x[i] = (int8_t)((int32_t)(conv_rand() % 15u) - 7);
    }
    for (i = 0; i < CONV_C_OUT * CONV_K; i++)
    {
        conv_w[i] = (int8_t)((int32_t)(conv_rand() % 11u) - 5);
    }
    for (i = 0; i < CONV_C_OUT; i++)
    {
        conv_bias[i] = (int32_t)(conv_rand() % 201u) - 100;
    }
}

static int8_t conv_requant(int32_t acc, int32_t bias)
{
    int64_t v = ((int64_t)acc + (int64_t)bias) * (int64_t)CONV_MULT;

    v = v >> CONV_SHIFT;
    v = v + (int64_t)CONV_ZP;
    if (CONV_RELU && (v < 0))
    {
        v = 0;
    }
    if (v > 127)  { v = 127; }
    if (v < -128) { v = -128; }
    return (int8_t)v;
}

/* Pack the A rows, the im2col B rows, the bias tile and the quant config. */
static void conv_pack(void)
{
    uint32_t ks, i, k, nt, j;

    for (ks = 0; ks < CONV_KS; ks++)
    {
        for (i = 0; i < 4u; i++)
        {
            for (k = 0; k < 4u; k++)
            {
                conv_wr8(CONV_W_OFF + (ks * 16u) + (4u * i) + k,
                         (uint8_t)conv_w[(i * CONV_K) + (ks * 4u) + k]);
            }
        }
    }

    for (ks = 0; ks < CONV_KS; ks++)
    {
        for (nt = 0; nt < CONV_NT; nt++)
        {
            for (k = 0; k < 4u; k++)
            {
                for (j = 0; j < 4u; j++)
                {
                    conv_wr8(CONV_B_OFF + ((ks * CONV_NT + nt) * 16u) + (4u * k) + j,
                             (uint8_t)conv_input_at((ks * 4u) + k, (nt * 4u) + j));
                }
            }
        }
    }

    for (i = 0; i < 4u; i++)
    {
        for (j = 0; j < 4u; j++)
        {
            conv_wr32(CONV_BIAS_OFF + (i * 16u) + (j * 4u), (uint32_t)conv_bias[i]);
        }
    }

    conv_wr32(CONV_CFG_OFF, MT_CFG(CONV_MULT, CONV_SHIFT, CONV_ZP, CONV_RELU));
    for (j = 4u; j < 16u; j += 4u)
    {
        conv_wr32(CONV_CFG_OFF + j, 0u);
    }
}

static void conv_build_golden(void)
{
    uint32_t m, n, k;

    for (n = 0; n < CONV_N; n++)
    {
        for (m = 0; m < CONV_C_OUT; m++)
        {
            int32_t acc = 0;

            for (k = 0; k < CONV_K; k++)
            {
                acc += (int32_t)conv_w[(m * CONV_K) + k] * (int32_t)conv_input_at(k, n);
            }
            conv_gold[((n / 4u) * 16u) + (4u * m) + (n % 4u)] =
                (uint8_t)conv_requant(acc, conv_bias[m]);
        }
    }
}

static int conv_run(uint32_t *cycles_out)
{
    uint32_t start, end, ks, nt;
    int rc;

    start = mt_rd_mcycle();

    /* Queue every command; the shim's FIFO drains a batch at a time, so the
     * only mandatory wait is the one before the output is inspected. */
    if ((rc = mt_push(MT_LOAD, MT_BUF_BASE + CONV_W_OFF,
                      MT_ROWS(CONV_UB_A, CONV_KS))) != 0) return rc;
    if ((rc = mt_push(MT_LOAD, MT_BUF_BASE + CONV_B_OFF,
                      MT_ROWS(CONV_UB_B, CONV_KS * CONV_NT))) != 0) return rc;
    if ((rc = mt_push(MT_LOAD, MT_BUF_BASE + CONV_BIAS_OFF,
                      MT_ROWS(CONV_UB_BIAS, 4u))) != 0) return rc;
    if ((rc = mt_push(MT_LOAD, MT_BUF_BASE + CONV_CFG_OFF,
                      MT_ROWS(CONV_UB_CFG, 1u))) != 0) return rc;

    for (nt = 0; nt < CONV_NT; nt++)
    {
        uint32_t crow = CONV_UB_C + (4u * nt);
        uint32_t brow = CONV_UB_B + nt;

        for (ks = 0; ks < CONV_KS; ks++)
        {
            uint32_t rs1 = MT_GEMM_RS1(CONV_UB_A + ks, brow + (ks * CONV_NT));
            uint32_t rs2 = MT_GEMM_RS2(crow, (ks != 0u) ? 1u : 0u);

            if ((rc = mt_push(MT_GEMM, rs1, rs2)) != 0)
            {
                rt_kprintf("mt_conv: GEMM nt=%u ks=%u failed (%d)\n",
                           (unsigned)nt, (unsigned)ks, rc);
                return rc;
            }
        }

        if ((rc = mt_push(MT_EPILOGUE, MT_EPI_RS1(crow, CONV_UB_BIAS),
                          MT_EPI_RS2(CONV_UB_OUT + nt, CONV_UB_CFG))) != 0)
        {
            rt_kprintf("mt_conv: EPILOGUE nt=%u failed (%d)\n", (unsigned)nt, rc);
            return rc;
        }
    }

    if ((rc = mt_push(MT_STORE, MT_BUF_BASE + CONV_OUT_OFF,
                      MT_ROWS(CONV_UB_OUT, CONV_NT))) != 0) return rc;

    if ((rc = mt_drain()) != 0) return rc;

    end = mt_rd_mcycle();
    *cycles_out = end - start;
    return 0;
}

static int mt_conv_command(int argc, char **argv)
{
    uint32_t cycles = 0u;
    uint32_t i;
    int rc;
    int mismatches = 0;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor 3x3 conv (6x6x4 -> 6x6x4, K=36) starting.\n");
    rt_kprintf("  %u GEMM + %u epilogue commands\n",
               (unsigned)(CONV_KS * CONV_NT), (unsigned)CONV_NT);

    conv_lcg = 0x2468ACE0u;
    conv_build_inputs();
    conv_pack();
    conv_build_golden();

    mt_reset_status();

    JYD_MMIO32(JYD_LED_ADDR) = 1u;
    rc = conv_run(&cycles);
    JYD_MMIO32(JYD_LED_ADDR) = 0u;

    if (rc != 0)
    {
        rt_kprintf("miniTensor conv FAILED, rc=%d\n", rc);
        halt(30);
    }

    for (i = 0; i < CONV_NT * 16u; i++)
    {
        uint8_t got = conv_rd8(CONV_OUT_OFF + i);

        if (got != conv_gold[i])
        {
            if (mismatches < 8)
            {
                rt_kprintf("  byte %u: got %02x expect %02x\n",
                           (unsigned)i, (unsigned)got, (unsigned)conv_gold[i]);
            }
            mismatches++;
        }
    }

    if (mismatches != 0)
    {
        rt_kprintf("miniTensor conv FAILED: %d/%u bytes wrong\n",
                   mismatches, (unsigned)(CONV_NT * 16u));
        halt(31);
    }

    rt_kprintf("miniTensor conv PASSED (all %u output bytes match CPU reference).\n",
               (unsigned)(CONV_NT * 16u));
    rt_kprintf("  conv cycles: %u\n", (unsigned)cycles);

    return 0;
}
MSH_CMD_EXPORT_ALIAS(mt_conv_command, mt_conv, run miniTensor 3x3 conv layer.);
