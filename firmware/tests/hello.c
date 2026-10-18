#include "board.h"

int main(void)
{
  uart_init(UART_DIV);
  uart_puts("HELLO ARES-P4\n");
  uart_putc('A');
  uart_putc('B');
  uart_putc('C');
  uart_putc('\n');
  halt(0);
  return 0;
}
