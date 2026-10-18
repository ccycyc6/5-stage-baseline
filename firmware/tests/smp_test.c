#include "board.h"

#define MBOX_SLOT(h, s) (MBOX_BASE + (h) * 0x40u + (s) * 4u)
#define MBOX_DOORBELL   (MBOX_BASE + 0x1000u)
#define MBOX_BARRIER    (MBOX_BASE + 0x2000u)
#define MBOX_BAR_STATUS (MBOX_BASE + 0x2004u)

void worker_entry(void)
{
  uint32_t hart = ares_rd_mhartid();
  volatile uint32_t *slot = (volatile uint32_t *)MBOX_SLOT(hart, 0);
  while (*slot == 0u) { }
  uint32_t v = *slot;
  *(volatile uint32_t *)(SCRATCH_BASE + 0x100u + hart * 4u) = v;
  ares_fence();
  *(volatile uint32_t *)MBOX_BARRIER = 1u << hart;
  for (;;) __asm__ volatile("wfi");
}

int main(void)
{
  uart_init(UART_DIV);
  if (ares_rd_mhartid() != 0) for (;;) __asm__ volatile("wfi");

  printf("\nARES-P4 SMP mailbox/barrier test\n");
  for (uint32_t h = 1; h < 4; h++)
    *(volatile uint32_t *)MBOX_SLOT(h, 0) = 0x100u + h;
  ares_fence();
  *(volatile uint32_t *)MBOX_DOORBELL = 0xEu;

  uint32_t spins = 0;
  while ((*(volatile uint32_t *)MBOX_BAR_STATUS & 0xEu) != 0xEu) {
    if (++spins > 20000000u) break;
  }
  int bad = 0;
  for (uint32_t h = 1; h < 4; h++) {
    uint32_t v = *(volatile uint32_t *)(SCRATCH_BASE + 0x100u + h * 4u);
    printf("  hart%u wrote %08x (expect %08x)\n", h, v, 0x100u + h);
    if (v != 0x100u + h) bad++;
  }
  printf("  barrier status=%08x\n", *(volatile uint32_t *)MBOX_BAR_STATUS);
  if (bad == 0 && spins <= 20000000u) printf("*** SMP TEST PASS ***\n");
  else printf("*** SMP TEST FAIL bad=%d spins=%u ***\n", bad, spins);
  halt(bad);
  return 0;
}
