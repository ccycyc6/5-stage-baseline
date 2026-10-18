#include "board.h"
#include "mt.h"

#define A_ADDR   0x10000000u
#define B_ADDR   0x10000020u
#define BIAS_ADDR 0x10000040u
#define CFG_ADDR 0x10000080u
#define OUT_ADDR 0x100000C0u

static void wr8(uint32_t addr, uint8_t v) { *(volatile uint8_t *)(uintptr_t)addr = v; }
static void wr32(uint32_t addr, uint32_t v) { *(volatile uint32_t *)(uintptr_t)addr = v; }
static uint32_t rd32(uint32_t addr) { return *(volatile uint32_t *)(uintptr_t)addr; }
static uint8_t rd8(uint32_t addr) { return *(volatile uint8_t *)(uintptr_t)addr; }

int main(void)
{
  uart_init(UART_DIV);
  if (ares_rd_mhartid() != 0) for (;;) __asm__ volatile("wfi");

  printf("\nMT DMA multi-row test\n");
  for (int i = 0; i < 1024; i++) wr8(0x10001000u + i, (uint8_t)(i * 5 + 1));
  int drc = mt_load(0x10001000u, 128, 64);
  printf("dma load rc=%d\n", drc);
  drc = mt_store(0x10002000u, 128, 64);
  printf("dma store rc=%d\n", drc);
  int dbad = 0;
  for (int i = 0; i < 1024; i++) {
    if (rd8(0x10002000u + i) != (uint8_t)(i * 5 + 1)) {
      if (dbad < 4) printf("dma bad[%d] got %02x\n", i, rd8(0x10002000u + i));
      dbad++;
    }
  }
  printf("dma bad=%d\n", dbad);

  printf("\nMT GEMM test: A(4x4 ones) * B(4x4 twos) -> 8\n");
  for (int i = 0; i < 16; i++) { wr8(A_ADDR + i, 1); wr8(B_ADDR + i, 2); }
  for (int i = 0; i < 64; i++) wr8(BIAS_ADDR + i, 0);
  for (int i = 0; i < 16; i++) wr8(CFG_ADDR + i, 0);
  wr32(CFG_ADDR, MT_CFG(1, 0, 0, 0));
  for (int i = 0; i < 4; i++) wr32(OUT_ADDR + 4*i, 0xA5A5A5A5u);

  int rc;
  rc = mt_load(A_ADDR, 0, 1);  printf("load A rc=%d\n", rc);
  rc = mt_load(B_ADDR, 1, 1);  printf("load B rc=%d\n", rc);
  rc = mt_load(BIAS_ADDR, 16, 4); printf("load bias rc=%d\n", rc);
  rc = mt_load(CFG_ADDR, 20, 1); printf("load cfg rc=%d\n", rc);
  rc = mt_store(0x10000200u, 0, 1); printf("dump A rc=%d\n", rc);
  rc = mt_store(0x10000210u, 1, 1); printf("dump B rc=%d\n", rc);
  for (int i = 0; i < 4; i++) printf("A[%d]=%08x B[%d]=%08x\n", i, rd32(0x10000200u+4*i), i, rd32(0x10000210u+4*i));
  rc = mt_exec(MT_GEMM, MT_GEMM_RS1(0, 1), MT_GEMM_RS2(8, 0)); printf("gemm rc=%d\n", rc);
  rc = mt_store(0x10000240u, 8, 4); printf("dump C rc=%d\n", rc);
  for (int i = 0; i < 16; i++) printf("C[%d]=%08x\n", i, rd32(0x10000240u+4*i));
  /* Accumulate eight more identical products: C = 9*8 = 72. */
  for (int acc_i = 0; acc_i < 8; acc_i++) {
    rc = mt_exec(MT_GEMM, MT_GEMM_RS1(0, 1), MT_GEMM_RS2(8, 1));
    if (rc != 0) printf("gemm acc %d rc=%d\n", acc_i, rc);
  }
  rc = mt_store(0x10000280u, 8, 4); printf("dump Cacc rc=%d\n", rc);
  for (int i = 0; i < 16; i++) printf("Cacc[%d]=%08x\n", i, rd32(0x10000280u+4*i));
  rc = mt_exec(MT_EPILOGUE, MT_EPI_RS1(8, 16), MT_EPI_RS2(24, 20)); printf("epi rc=%d\n", rc);
  rc = mt_store(OUT_ADDR, 24, 1); printf("store rc=%d\n", rc);

  int bad = 0;
  for (int i = 0; i < 4; i++) {
    uint32_t v = rd32(OUT_ADDR + 4*i);
    printf("out[%d]=%08x\n", i, v);
    if (v != 0x48484848u) bad++;
  }
  if (bad == 0) printf("*** MT GEMM + ACCUM + EPILOGUE PASS ***\n");
  else printf("*** MT GEMM FAIL bad=%d ***\n", bad);
  halt(bad);
  return 0;
}