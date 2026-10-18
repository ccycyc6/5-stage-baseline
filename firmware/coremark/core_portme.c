#include "coremark.h"
#include "board.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

static CORE_TICKS start_cycles, stop_cycles;
volatile unsigned long long ares_last_coremark_cycles;

void start_time(void)
{
  start_cycles = ares_rd_mcycle64();
}

void stop_time(void)
{
  stop_cycles = ares_rd_mcycle64();
  ares_last_coremark_cycles = stop_cycles - start_cycles;
}

CORE_TICKS get_time(void)
{
  return stop_cycles - start_cycles;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
  return (double)ticks / (double)CPU_HZ;
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[])
{
  (void)argc;
  (void)argv;
  p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
  p->portable_id = 0;
}