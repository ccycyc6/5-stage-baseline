#include "board.h"

static void wr8(uint32_t a, uint8_t v) { *(volatile uint8_t *)(uintptr_t)a = v; }
static uint8_t rd8(uint32_t a) { return *(volatile uint8_t *)(uintptr_t)a; }

int main(void)
{
  uart_init(UART_DIV);
  if (ares_rd_mhartid() != 0) for (;;) __asm__ volatile("wfi");

  uint32_t base = 0x10000000u;
  int bad = 0;
  printf("scratch byte test at %08x\n", base);
  for (uint32_t i = 0; i < 65536; i++) wr8(base + i, (uint8_t)(i * 7 + 3));
  for (uint32_t i = 0; i < 65536; i++) {
    uint8_t v = rd8(base + i);
    uint8_t e = (uint8_t)(i * 7 + 3);
    if (v != e) {
      if (bad < 8) printf("bad[%u] got %02x exp %02x\n", i, v, e);
      bad++;
    }
  }
  printf("scratch test bad=%d\n", bad);
  halt(bad);
  return 0;
}