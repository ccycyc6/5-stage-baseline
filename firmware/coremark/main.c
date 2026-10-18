#include "board.h"
#include "coremark/coremark.h"

extern int coremark_main(void);

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
  printf("ARES-P4 CoreMark 1.0 / RV32IM / 100 MHz\n");
  printf("PG2L200H 4xARES-L + miniTensor\n");
  printf("==================================================\n");

  int rc = coremark_main();

  extern volatile unsigned long long ares_last_coremark_cycles;
  unsigned long long cyc = ares_last_coremark_cycles;
  if (cyc == 0) cyc = 1;
  unsigned int score_millis = (unsigned int)((unsigned long long)ITERATIONS * 1000000000ULL / cyc);
  unsigned int ips = (unsigned int)((unsigned long long)ITERATIONS * 100000000ULL / cyc);
  printf("\nARES-P4 timed cycles : %u\n", (unsigned int)cyc);
  printf("ARES-P4 CoreMark/MHz : %u.%03u\n", score_millis / 1000u, score_millis % 1000u);
  printf("ARES-P4 Iterations/s : %u\n", ips);
  printf("CoreMark main returned %d\n", rc);
  halt(0);
  return 0;
}