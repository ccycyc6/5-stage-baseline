/*
 * mt_app.c -- miniTensor bring-up demo + self-check for RT-Thread on MundusJyd.
 *
 * Runs the same K=12 4x4 INT8 GEMM that tb/top/tb_mini_tensor_npc.sv uses,
 * compares the accelerator result against a CPU reference computed in this
 * file, and exercises the VPU path as well.
 *
 *   A (4x12 int8) x B (12x4 int8) -> C (4x4 int32) -> requantise -> 16 int8
 *
 * Register with the shell as:  msh > mt_gemm
 */
#include <rtthread.h>
#include <finsh.h>

#include "board.h"
#include "mt.h"

/* -------------------------------------------------------------------------- */
/* Scratch buffer layout inside the uncached alias window                     */
/* -------------------------------------------------------------------------- */
#define A_OFF     0x0000u
#define B_OFF     0x0030u
#define BIAS_OFF  0x0100u
#define CFG_OFF   0x0140u
#define OUT_OFF   0x0200u
#define VEC_A_OFF 0x0300u
#define VEC_B_OFF 0x0310u
#define VEC_C_OFF 0x0320u
#define MTEST_OFF 0x0400u

/* Addresses above the old 256 KiB DRAM window.  They are outside the D-cache's
 * cacheable range, so the CPU reaches them uncached, and outside the
 * 0x8030_0000-0x8033_FFFF mirror, so they are plain extended memory. */
#define EXT_A_ADDR 0x80400000u
#define EXT_B_ADDR 0x80F00000u

#define K_DIM     12u
#define A_BYTES   (3u * 16u)
#define B_BYTES   (3u * 16u)

/* UB row plan (identical to the reference testbench) */
#define UB_A0     0u
#define UB_B0     3u
#define UB_C      8u
#define UB_BIAS   16u
#define UB_CFG    20u
#define UB_OUT    24u
#define UB_VECA   32u
#define UB_VECB   33u
#define UB_VECC   34u

static volatile uint8_t *const mt_buf = (volatile uint8_t *)(uintptr_t)MT_BUF_BASE;

static void buf_wr32(uint32_t off, uint32_t value)
{
    *(volatile uint32_t *)(uintptr_t)(MT_BUF_BASE + off) = value;
}

static void buf_wr8(uint32_t off, uint8_t value)
{
    mt_buf[off] = value;
}

static uint8_t buf_rd8(uint32_t off)
{
    return mt_buf[off];
}

/* -------------------------------------------------------------------------- */
/* Test vectors and CPU reference model                                       */
/* -------------------------------------------------------------------------- */
static int8_t  g_a[4][K_DIM];
static int8_t  g_b[K_DIM][4];
static int32_t g_bias[4][4];
static int32_t g_acc[4][4];

#define MULTIPLIER  16
#define SHIFT       2
#define ZERO_POINT  (-5)
#define RELU_ON     1

static uint32_t g_lcg = 0x12345678u;

static uint32_t lcg_next(void)
{
    g_lcg = (g_lcg * 1103515245u) + 12345u;
    return g_lcg;
}

/* Pack A and B into the UB row format the accelerator expects:
 *   A UB row t, byte b  -> A[b/4][4t + b%4]
 *   B UB row t, byte b  -> B[4t + b/4][b%4]
 * Pack bias as four little-endian int32 per row, and the quant config. */
static void build_inputs(void)
{
    uint32_t t, b, i, j;

    for (i = 0; i < 4u; i++)
    {
        for (j = 0; j < K_DIM; j++)
        {
            g_a[i][j] = (int8_t)((int32_t)(lcg_next() % 15u) - 7);
        }
    }
    for (i = 0; i < K_DIM; i++)
    {
        for (j = 0; j < 4u; j++)
        {
            g_b[i][j] = (int8_t)((int32_t)(lcg_next() % 15u) - 7);
        }
    }
    for (i = 0; i < 4u; i++)
    {
        for (j = 0; j < 4u; j++)
        {
            g_bias[i][j] = (int32_t)(lcg_next() % 2001u) - 1000;
        }
    }

    for (t = 0; t < 3u; t++)
    {
        for (b = 0; b < 16u; b++)
        {
            buf_wr8(A_OFF + (t * 16u) + b, (uint8_t)g_a[b >> 2][(4u * t) + (b & 3u)]);
        }
    }
    for (t = 0; t < 3u; t++)
    {
        for (b = 0; b < 16u; b++)
        {
            buf_wr8(B_OFF + (t * 16u) + b, (uint8_t)g_b[(4u * t) + (b >> 2)][b & 3u]);
        }
    }
    for (i = 0; i < 4u; i++)
    {
        for (j = 0; j < 4u; j++)
        {
            buf_wr32(BIAS_OFF + (i * 16u) + (j * 4u), (uint32_t)g_bias[i][j]);
        }
    }
    buf_wr32(CFG_OFF, MT_CFG(MULTIPLIER, SHIFT, ZERO_POINT, RELU_ON));
    buf_wr32(CFG_OFF + 4u, 0u);
    buf_wr32(CFG_OFF + 8u, 0u);
    buf_wr32(CFG_OFF + 12u, 0u);

    for (j = 0; j < 4u; j++)
    {
        buf_wr32(OUT_OFF + (j * 4u), 0xA5A5A5A5u);
    }
}

static void build_golden(void)
{
    uint32_t i, j, k;

    for (i = 0; i < 4u; i++)
    {
        for (j = 0; j < 4u; j++)
        {
            int32_t sum = 0;

            for (k = 0; k < K_DIM; k++)
            {
                sum += (int32_t)g_a[i][k] * (int32_t)g_b[k][j];
            }
            g_acc[i][j] = sum;
        }
    }
}

static int8_t quantise(int32_t acc, int32_t bias)
{
    int64_t sum = (int64_t)acc + (int64_t)bias;
    int64_t scaled = sum * (int64_t)MULTIPLIER;
    int64_t shifted = scaled >> SHIFT;          /* arithmetic shift */
    int64_t q = shifted + (int64_t)ZERO_POINT;

    if (RELU_ON && (q < 0))
    {
        q = 0;
    }
    if (q > 127)
    {
        q = 127;
    }
    if (q < -128)
    {
        q = -128;
    }

    return (int8_t)q;
}

/* -------------------------------------------------------------------------- */
/* Command sequence                                                           */
/* -------------------------------------------------------------------------- */
static int run_gemm(uint32_t *cycles_out)
{
    uint32_t start, end;
    int rc;

    start = mt_rd_mcycle();

    if ((rc = mt_load(MT_BUF_BASE + A_OFF, UB_A0, 3u)) != 0)
    {
        rt_kprintf("mt: LOAD A failed (%d)\n", rc);
        return rc;
    }
    if ((rc = mt_load(MT_BUF_BASE + B_OFF, UB_B0, 3u)) != 0)
    {
        rt_kprintf("mt: LOAD B failed (%d)\n", rc);
        return rc;
    }
    if ((rc = mt_load(MT_BUF_BASE + BIAS_OFF, UB_BIAS, 4u)) != 0)
    {
        rt_kprintf("mt: LOAD bias failed (%d)\n", rc);
        return rc;
    }
    if ((rc = mt_load(MT_BUF_BASE + CFG_OFF, UB_CFG, 1u)) != 0)
    {
        rt_kprintf("mt: LOAD config failed (%d)\n", rc);
        return rc;
    }

    /* C = A0*B0, then accumulate A1*B1 and A2*B2 for K=12. */
    if ((rc = mt_exec(MT_GEMM, MT_GEMM_RS1(UB_A0 + 0u, UB_B0 + 0u),
                      MT_GEMM_RS2(UB_C, 0u))) != 0)
    {
        rt_kprintf("mt: GEMM 0 failed (%d)\n", rc);
        return rc;
    }
    if ((rc = mt_exec(MT_GEMM, MT_GEMM_RS1(UB_A0 + 1u, UB_B0 + 1u),
                      MT_GEMM_RS2(UB_C, 1u))) != 0)
    {
        rt_kprintf("mt: GEMM 1 failed (%d)\n", rc);
        return rc;
    }
    if ((rc = mt_exec(MT_GEMM, MT_GEMM_RS1(UB_A0 + 2u, UB_B0 + 2u),
                      MT_GEMM_RS2(UB_C, 1u))) != 0)
    {
        rt_kprintf("mt: GEMM 2 failed (%d)\n", rc);
        return rc;
    }

    if ((rc = mt_exec(MT_EPILOGUE, MT_EPI_RS1(UB_C, UB_BIAS),
                      MT_EPI_RS2(UB_OUT, UB_CFG))) != 0)
    {
        rt_kprintf("mt: EPILOGUE failed (%d)\n", rc);
        return rc;
    }

    if ((rc = mt_store(MT_BUF_BASE + OUT_OFF, UB_OUT, 1u)) != 0)
    {
        rt_kprintf("mt: STORE failed (%d)\n", rc);
        return rc;
    }

    end = mt_rd_mcycle();
    *cycles_out = end - start;

    return 0;
}

/* Exercise the VPU: out = relu(max(A + B, A + B)) is overkill; instead run
 * ADD8, MAX8 and RELU8 and check each against the CPU model. */
static int run_vector(void)
{
    uint32_t i;
    int rc;
    int8_t a[16], b[16], expect[16];

    for (i = 0; i < 16u; i++)
    {
        a[i] = (int8_t)((int32_t)(lcg_next() % 21u) - 10);
        b[i] = (int8_t)((int32_t)(lcg_next() % 21u) - 10);
        buf_wr8(VEC_A_OFF + i, (uint8_t)a[i]);
        buf_wr8(VEC_B_OFF + i, (uint8_t)b[i]);
    }

    if ((rc = mt_load(MT_BUF_BASE + VEC_A_OFF, UB_VECA, 1u)) != 0) return rc;
    if ((rc = mt_load(MT_BUF_BASE + VEC_B_OFF, UB_VECB, 1u)) != 0) return rc;

    /* ADD8: per-lane 8-bit wrap */
    if ((rc = mt_exec(MT_VEC_ADD8, MT_VEC_RS1(UB_VECA, UB_VECB), UB_VECC)) != 0) return rc;
    if ((rc = mt_store(MT_BUF_BASE + VEC_C_OFF, UB_VECC, 1u)) != 0) return rc;
    for (i = 0; i < 16u; i++)
    {
        expect[i] = (int8_t)(uint8_t)((uint8_t)a[i] + (uint8_t)b[i]);
        if ((int8_t)buf_rd8(VEC_C_OFF + i) != expect[i])
        {
            rt_kprintf("mt: ADD8 lane %u: got %d expect %d\n",
                       i, (int)buf_rd8(VEC_C_OFF + i), (int)expect[i]);
            return -10;
        }
    }

    /* MAX8: signed max */
    if ((rc = mt_exec(MT_VEC_MAX8, MT_VEC_RS1(UB_VECA, UB_VECB), UB_VECC)) != 0) return rc;
    if ((rc = mt_store(MT_BUF_BASE + VEC_C_OFF, UB_VECC, 1u)) != 0) return rc;
    for (i = 0; i < 16u; i++)
    {
        expect[i] = (a[i] > b[i]) ? a[i] : b[i];
        if ((int8_t)buf_rd8(VEC_C_OFF + i) != expect[i])
        {
            rt_kprintf("mt: MAX8 lane %u: got %d expect %d\n",
                       i, (int)buf_rd8(VEC_C_OFF + i), (int)expect[i]);
            return -11;
        }
    }

    /* RELU8: uses operand A only */
    if ((rc = mt_exec(MT_VEC_RELU8, MT_VEC_RS1(UB_VECA, UB_VECB), UB_VECC)) != 0) return rc;
    if ((rc = mt_store(MT_BUF_BASE + VEC_C_OFF, UB_VECC, 1u)) != 0) return rc;
    for (i = 0; i < 16u; i++)
    {
        expect[i] = (a[i] > 0) ? a[i] : (int8_t)0;
        if ((int8_t)buf_rd8(VEC_C_OFF + i) != expect[i])
        {
            rt_kprintf("mt: RELU8 lane %u: got %d expect %d\n",
                       i, (int)buf_rd8(VEC_C_OFF + i), (int)expect[i]);
            return -12;
        }
    }

    return 0;
}

/* Prove that external memory beyond the on-chip 256 KiB works from both
 * masters: CPU uncached accesses, and the 128-bit DMA. */
#define MTEST_BYTES 64u
#define UB_M1       40u
#define UB_M2       44u

static int run_memtest(void)
{
    uint8_t pattern[MTEST_BYTES];
    uint32_t i;
    int rc;

    for (i = 0; i < MTEST_BYTES; i++)
    {
        pattern[i] = (uint8_t)((i * 7u) + 3u);
    }

    /* 1. CPU stores to an address past the old 256 KiB boundary. */
    for (i = 0; i < MTEST_BYTES; i++)
    {
        *(volatile uint8_t *)(uintptr_t)(EXT_A_ADDR + i) = pattern[i];
    }

    /* 2. CPU loads it back.  This also exercises the bridge's store-to-load
     *    forwarding at the widened address. */
    for (i = 0; i < MTEST_BYTES; i++)
    {
        uint8_t got = *(volatile uint8_t *)(uintptr_t)(EXT_A_ADDR + i);

        if (got != pattern[i])
        {
            rt_kprintf("mt: CPU readback 0x%08x: got %02x expect %02x\n",
                       (unsigned)(EXT_A_ADDR + i), (unsigned)got, (unsigned)pattern[i]);
            return -20;
        }
    }

    /* 3. DMA: extended memory -> UB. */
    if ((rc = mt_load(EXT_A_ADDR, UB_M1, 4u)) != 0) return -21;

    /* 4. DMA: UB -> an address near the top of the 15 MiB window. */
    if ((rc = mt_store(EXT_B_ADDR, UB_M1, 4u)) != 0) return -22;

    /* 5. DMA: that far address -> a second UB window. */
    if ((rc = mt_load(EXT_B_ADDR, UB_M2, 4u)) != 0) return -23;

    /* 6. DMA: UB -> the uncached scratch, where the CPU can inspect it. */
    if ((rc = mt_store(MT_BUF_BASE + MTEST_OFF, UB_M2, 4u)) != 0) return -24;

    for (i = 0; i < MTEST_BYTES; i++)
    {
        uint8_t got = buf_rd8(MTEST_OFF + i);

        if (got != pattern[i])
        {
            rt_kprintf("mt: DMA round trip byte %u: got %02x expect %02x\n",
                       (unsigned)i, (unsigned)got, (unsigned)pattern[i]);
            return -25;
        }
    }

    return 0;
}

/* -------------------------------------------------------------------------- */
/* Shell command                                                              */
/* -------------------------------------------------------------------------- */
static int mt_gemm_command(int argc, char **argv)
{
    uint32_t cycles = 0u;
    uint32_t i, j;
    int rc;
    int mismatches = 0;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor self-check starting.\n");

    g_lcg = 0x12345678u;
    build_inputs();
    build_golden();

    /* Make sure the adapter is idle before the first kick. */
    mt_reset_status();

    /* LED0 brackets the accelerator work so the simulation's
     * --stats-window=led0 reports cover exactly this section, the same way
     * competition_app.c brackets CoreMark. */
    JYD_MMIO32(JYD_LED_ADDR) = 1u;
    rc = run_gemm(&cycles);
    JYD_MMIO32(JYD_LED_ADDR) = 0u;

    if (rc != 0)
    {
        rt_kprintf("miniTensor GEMM failed, rc=%d\n", rc);
        halt(20);
    }

    for (i = 0; i < 4u; i++)
    {
        for (j = 0; j < 4u; j++)
        {
            int8_t got = (int8_t)buf_rd8(OUT_OFF + (i * 4u) + j);
            int8_t exp = quantise(g_acc[i][j], g_bias[i][j]);

            if (got != exp)
            {
                rt_kprintf("  mismatch C[%u][%u]: got %d expect %d\n",
                           i, j, (int)got, (int)exp);
                mismatches++;
            }
        }
    }

    if (mismatches != 0)
    {
        rt_kprintf("miniTensor GEMM FAILED: %d/16 lanes wrong\n", mismatches);
        halt(21);
    }
    rt_kprintf("miniTensor GEMM PASSED (K=12, 4x4 INT8, requant+ReLU).\n");
    rt_kprintf("  command chain cycles: %u\n", cycles);

    rc = run_vector();
    if (rc != 0)
    {
        rt_kprintf("miniTensor VPU FAILED, rc=%d\n", rc);
        halt(22);
    }
    rt_kprintf("miniTensor VPU PASSED (ADD8 / MAX8 / RELU8).\n");

    rt_kprintf("miniTensor self-check OK.\n");
    return 0;
}
MSH_CMD_EXPORT_ALIAS(mt_gemm_command, mt_gemm, run miniTensor GEMM self-check.);

static int mt_memtest_command(int argc, char **argv)
{
    int rc;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor extended-memory test (CPU + DMA, >256 KiB).\n");

    rc = run_memtest();
    if (rc != 0)
    {
        rt_kprintf("miniTensor extended-memory test FAILED, rc=%d\n", rc);
        halt(23);
    }

    rt_kprintf("miniTensor extended-memory test PASSED (0x8040_0000 and 0x80F0_0000).\n");
    return 0;
}
MSH_CMD_EXPORT_ALIAS(mt_memtest_command, mt_memtest, run miniTensor >256KiB memory test.);

/* --------------------------------------------------------------------------
 * Cost breakdown.  Every MT command costs four MMIO stores plus a status poll
 * loop; before optimising anything it is worth knowing which of those actually
 * dominates on this core.
 * ------------------------------------------------------------------------ */
static volatile uint32_t perf_sink;
static volatile uint32_t perf_scratch[64];

static void perf_report(const char *label, uint32_t cycles, uint32_t iters)
{
    rt_kprintf("  %s: %u cycles/op\n", label, (unsigned)(cycles / (iters ? iters : 1u)));
}

static int mt_perf_command(int argc, char **argv)
{
    const uint32_t N = 2000u;
    uint32_t t0, t1, i;

    (void)argc;
    (void)argv;

    rt_kprintf("miniTensor cost breakdown (%u iterations each).\n", (unsigned)N);
    mt_reset_status();

    t0 = mt_rd_mcycle();
    for (i = 0; i < N; i++) { perf_sink = MT_MMIO32(MT_STATUS); }
    t1 = mt_rd_mcycle();
    perf_report("MMIO read  (MT_STATUS)", t1 - t0, N);

    t0 = mt_rd_mcycle();
    for (i = 0; i < N; i++) { MT_MMIO32(MT_INSTR) = 0x0000000Bu; }
    t1 = mt_rd_mcycle();
    perf_report("MMIO write (MT_INSTR) ", t1 - t0, N);

    t0 = mt_rd_mcycle();
    for (i = 0; i < N; i++) { *(volatile uint32_t *)(uintptr_t)MT_BUF_BASE = i; }
    t1 = mt_rd_mcycle();
    perf_report("uncached DRAM store   ", t1 - t0, N);

    t0 = mt_rd_mcycle();
    for (i = 0; i < N; i++) { perf_sink = *(volatile uint32_t *)(uintptr_t)MT_BUF_BASE; }
    t1 = mt_rd_mcycle();
    perf_report("uncached DRAM load    ", t1 - t0, N);

    t0 = mt_rd_mcycle();
    for (i = 0; i < N; i++) { perf_scratch[i & 63u] = i; }
    t1 = mt_rd_mcycle();
    perf_report("cached DRAM store     ", t1 - t0, N);

    t0 = mt_rd_mcycle();
    for (i = 0; i < (N / 4u); i++)
    {
        (void)mt_exec(MT_LOAD, MT_BUF_BASE, MT_ROWS(0u, 1u));
    }
    t1 = mt_rd_mcycle();
    perf_report("MT_LOAD, poll each   ", t1 - t0, N / 4u);

    /* The way net_conv drives it: queue without polling, drain once. */
    t0 = mt_rd_mcycle();
    for (i = 0; i < N; i++)
    {
        (void)mt_push(MT_LOAD, MT_BUF_BASE, MT_ROWS(0u, 1u));
    }
    (void)mt_drain();
    t1 = mt_rd_mcycle();
    perf_report("MT_LOAD, batched     ", t1 - t0, N);

    /* Same again but with a GEMM, which is what the convolution spends its
     * time on (2 UB reads + 10 MXU cycles + 4 UB writes). */
    mt_reset_status();
    t0 = mt_rd_mcycle();
    for (i = 0; i < N; i++)
    {
        (void)mt_push(MT_GEMM, MT_GEMM_RS1(0u, 1u), MT_GEMM_RS2(8u, 0u));
    }
    (void)mt_drain();
    t1 = mt_rd_mcycle();
    perf_report("MT_GEMM, batched     ", t1 - t0, N);

    return 0;
}
MSH_CMD_EXPORT_ALIAS(mt_perf_command, mt_perf, measure miniTensor MMIO costs.);
