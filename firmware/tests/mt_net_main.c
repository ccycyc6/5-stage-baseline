#include "board.h"

extern int mt_net_command(int argc, char **argv);

int main(void)
{
  uart_init(UART_DIV);
  if (ares_rd_mhartid() != 0) for (;;) __asm__ volatile("wfi");
  uart_puts("HELLO\n");
  printf("\nMT synthetic network regression\n");
  int rc = mt_net_command(0, 0);
  printf("mt_net_command returned %d\n", rc);
  halt(rc);
  return 0;
}