#include "board.h"
#include "coremark/coremark.h"

extern int coremark_main(void);

/* Measured core clock, override with -DCPU_HZ=<hz> for board builds. */
#ifndef CPU_HZ
#define CPU_HZ 100000000u
#endif

int main(void)
{
  uint32_t hart = ares_rd_mhartid();
  uart_init(UART_DIV);

  if (hart != 0) {
    /* Worker harts wait for the control plane. */
    for (;;) {
      __asm__ volatile("wfi");
    }
  }

  printf("\n==================================================\n");
  printf("ARES-P4 CoreMark 1.0 / RV32IM\n");
  printf("Pangu 200Pro+ / PG2L200H / %u MHz\n", (unsigned)(CPU_HZ / 1000000u));
  printf("4x ARES-L 5-stage + 2-way L1 + shared L2\n");
  printf("==================================================\n");

  int rc = coremark_main();

  extern volatile unsigned long long ares_last_coremark_cycles;
  unsigned long long cyc = ares_last_coremark_cycles;
  if (cyc == 0) cyc = 1;
  /* score_millis = ITERATIONS * CPU_HZ / cycles / 1000 */
  unsigned long long num = (unsigned long long)ITERATIONS * (unsigned long long)CPU_HZ;
  unsigned int score_millis = (unsigned int)(num / cyc);
  unsigned int ips = (unsigned int)((unsigned long long)ITERATIONS * (unsigned long long)CPU_HZ / cyc);
  unsigned int secs_ms = (unsigned int)(num ? (unsigned long long)cyc * 1000ULL / (unsigned long long)CPU_HZ : 0);
  printf("\nARES-P4 timed cycles : %u\n", (unsigned int)cyc);
  printf("ARES-P4 time        : %u ms\n", secs_ms);
  printf("ARES-P4 CoreMark/MHz : %u.%03u\n", score_millis / 1000u, score_millis % 1000u);
  printf("ARES-P4 Iterations/s : %u\n", ips);
  printf("CoreMark main returned %d\n", rc);
  halt(0);
  return 0;
}
