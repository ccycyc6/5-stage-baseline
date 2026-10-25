/*
 * ARES-P4 board vision demo (CPU only, no miniTensor required).
 *
 *   d  run the built-in self test (5 shapes x 4 variants)
 *   u  upload a 32x32 8-bit raw frame over UART, then classify it
 *   a  print a 16x16 ASCII preview of the last frame
 *   m  print this menu
 *
 * Frame format for 'u': exactly 1024 bytes, row major, 0 = black background,
 * 255 = shape.  tools/img2raw.py converts a PGM/PPM/BMP photo to that file and
 * tools/send_image.ps1 pushes it over the serial port.
 */
#include "vision.h"

/* The UART data register is shared: writing it transmits, reading it returns
 * the last received byte (and clears the rx-valid flag). */
#define UART_RX_DATA UART_TX

static uint8_t frame[VIS_N];
static uint32_t last_cycles;

static int uart_rx_ready(void)
{
  return (ares_mmio_read(UART_STATUS) & 2u) != 0u;
}

int vis_getc(void)
{
  if (!uart_rx_ready()) return -1;
  return (int)(ares_mmio_read(UART_RX_DATA) & 0xFFu);
}

int vis_getc_timeout(int ticks)
{
  while (ticks-- > 0) {
    int c = vis_getc();
    if (c >= 0) return c;
  }
  return -1;
}

static void print_result(int cls, int dist)
{
  if (cls == VIS_UNKNOWN) {
    printf("  result: UNKNOWN (best distance %d)\n", dist);
  } else {
    int conf = 100 - (dist * 100) / 256;
    if (conf < 0) conf = 0;
    if (conf > 100) conf = 100;
    printf("  result: %s  distance %d  confidence %d%%\n",
           vision_class_name[cls], dist, conf);
  }
}

static int self_test(void)
{
  static const struct {
    int r, dx, dy, noise;
  } var[4] = {
    { 12,  0,  0,  0 },
    { 12,  0,  0, 24 },
    { 11,  3, -2,  8 },
    { 13, -3,  3, 16 },
  };
  int c, v, pass = 0, total = 0;

  printf("\n--- built-in self test (5 classes x 4 variants) ---\n");
  for (c = 0; c < VIS_CLASSES; c++) {
    printf("%-9s", vision_class_name[c]);
    for (v = 0; v < 4; v++) {
      int dist = 0, cls;
      uint64_t t0, t1;

      vision_render(c, frame, VIS_W / 2 + var[v].dx, VIS_H / 2 + var[v].dy,
                    var[v].r, var[v].noise, 0x1234u + (uint32_t)(c * 7 + v));
      t0 = ares_rd_mcycle64();
      cls = vision_classify(frame, &dist);
      t1 = ares_rd_mcycle64();
      last_cycles = (uint32_t)(t1 - t0);
      total++;
      if (cls == c) { pass++; printf("  ok "); }
      else          { printf("  XX "); }
    }
    printf("\n");
  }
  printf("self test: %d/%d correct, last classify %u cycles\n",
         pass, total, (unsigned)last_cycles);
  return pass == total;
}

static void menu(void)
{
  printf("\ncommands: d=self test  u=upload 32x32 frame  a=preview  m=menu\n");
}

static void upload(void)
{
  int i, dist = 0, cls;
  uint64_t t0, t1;

  printf("\nready for %d bytes (32x32 raw)\n", VIS_N);
  /* One byte at 115200 is about 234 core clocks; allow a generous window. */
  for (i = 0; i < VIS_N; i++) {
    int c = vis_getc_timeout(4000000);
    if (c < 0) {
      printf("timeout after %d bytes\n", i);
      return;
    }
    frame[i] = (uint8_t)c;
  }
  printf("got %d bytes\n", VIS_N);

  t0 = ares_rd_mcycle64();
  cls = vision_classify(frame, &dist);
  t1 = ares_rd_mcycle64();
  last_cycles = (uint32_t)(t1 - t0);

  vision_dump(frame);
  print_result(cls, dist);
  printf("  classify took %u cycles (%u us at 27 MHz)\n",
         (unsigned)last_cycles, (unsigned)(last_cycles / 27u));
}

int main(void)
{
  uart_init(UART_DIV);

  printf("\n==================================================\n");
  printf("ARES-P4 vision demo / RV32IM / CPU only\n");
  printf("Pangu 200Pro+ / PG2L200H / %u MHz\n", (unsigned)(CPU_HZ / 1000000u));
  printf("32x32 frame -> 16x16 features -> 5 shape classes\n");
  printf("==================================================\n");

  vision_init_prototypes();
  self_test();
  menu();

  for (;;) {
    int c = vis_getc();
    if (c < 0) continue;
    switch (c) {
      case 'd': case 'D': self_test(); break;
      case 'u': case 'U': upload(); break;
      case 'a': case 'A': vision_dump(frame); break;
      case 'm': case 'M': case '?': menu(); break;
      default: break;
    }
  }
  return 0;
}