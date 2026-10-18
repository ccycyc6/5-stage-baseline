#include "board.h"

extern int yolo_run(void);

int main(void)
{
  uint32_t hart = ares_rd_mhartid();
  uart_init(UART_DIV);

  if (hart != 0) {
    for (;;) __asm__ volatile("wfi");
  }

  printf("\n==================================================\n");
  printf("ARES-P4 YOLO detector / miniTensor INT8\n");
  printf("PG2L200H 4xARES-L, one miniTensor per core\n");
  printf("==================================================\n");

  int rc = yolo_run();

  printf("YOLO run returned %d\n", rc);
  halt(rc);
  return 0;
}
