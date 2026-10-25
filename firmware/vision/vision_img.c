/*
 * ARES-P4 vision demo: shape recognition on a 32x32 frame, integer only.
 *
 * Pipeline
 *   1. threshold  : mid point between the frame min and max
 *   2. crop       : bounding box of the foreground, resampled to 16x16
 *   3. normalise  : subtract the mean, scale so sum|v| == 256
 *   4. classify   : minimum L1 distance to five rendered prototypes
 *
 * Everything is fixed point so the same code can later be compared against a
 * hardware accelerated version.
 */
#include "vision.h"

const char *const vision_class_name[VIS_CLASSES] = {
  "circle", "square", "triangle", "cross", "ring"
};

static int16_t proto[VIS_CLASSES][VIS_FEAT];

/* ------------------------------------------------------------------ render */
static uint32_t rnd_state;

static int rnd(int range)
{
  rnd_state = rnd_state * 1664525u + 1013904223u;
  return (int)((rnd_state >> 16) % (uint32_t)range);
}

void vision_render(int cls, uint8_t *img, int cx, int cy, int r,
                   int noise, uint32_t seed)
{
  int x, y;
  int rin = (r * 55) / 100;

  rnd_state = seed ? seed : 1u;

  for (y = 0; y < VIS_H; y++) {
    for (x = 0; x < VIS_W; x++) {
      int dx = x - cx, dy = y - cy;
      int on = 0;
      switch (cls) {
        case VIS_CIRCLE:
          on = (dx * dx + dy * dy) <= r * r;
          break;
        case VIS_SQUARE:
          on = (dx >= -r && dx <= r && dy >= -r && dy <= r);
          break;
        case VIS_TRIANGLE: {
          /* apex at (cx, cy-r), base at y = cy+r, half width grows linearly */
          int h = y - (cy - r);
          if (h >= 0 && h <= 2 * r) {
            int half = (h * r) / (2 * r);
            on = (dx >= -half && dx <= half);
          }
          break;
        }
        case VIS_CROSS:
          on = ((dx >= -r / 3 && dx <= r / 3 && dy >= -r && dy <= r) ||
                (dy >= -r / 3 && dy <= r / 3 && dx >= -r && dx <= r));
          break;
        case VIS_RING:
          on = (dx * dx + dy * dy) <= r * r && (dx * dx + dy * dy) >= rin * rin;
          break;
        default:
          on = 0;
          break;
      }
      img[y * VIS_W + x] = on ? 255 : 0;
    }
  }

  if (noise) {
    for (y = 0; y < VIS_N; y++) {
      int v = (int)img[y] + (rnd(2 * noise + 1) - noise);
      if (v < 0) v = 0;
      if (v > 255) v = 255;
      img[y] = (uint8_t)v;
    }
  }
}

/* --------------------------------------------------------------- features */
/* Threshold, find the foreground bounding box, rescale the shape so its
 * longer side is 24 px on a 32x32 canvas, box-filter down to 16x16, remove the
 * mean and normalise sum|v| to 256.  Returns 0 for a flat/empty frame. */
static int extract(const uint8_t *img, int16_t *out)
{
  int i, x, y;
  int lo = 255, hi = 0, thr;
  int x0 = VIS_W, x1 = -1, y0 = VIS_H, y1 = -1;
  int bw, bh, m, cx, cy;
  int32_t sum = 0, l1 = 0;
  static uint8_t canvas[VIS_N];

  for (i = 0; i < VIS_N; i++) {
    if (img[i] < lo) lo = img[i];
    if (img[i] > hi) hi = img[i];
  }
  if (hi - lo < 24) return 0;
  thr = (lo + hi) / 2;

  for (y = 0; y < VIS_H; y++) {
    for (x = 0; x < VIS_W; x++) {
      if (img[y * VIS_W + x] > thr) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < x0 || y1 < y0) return 0;

  bw = x1 - x0 + 1;
  bh = y1 - y0 + 1;
  m  = (bw > bh) ? bw : bh;
  cx = (x0 + x1) / 2;
  cy = (y0 + y1) / 2;

  for (y = 0; y < VIS_H; y++) {
    int sy = cy + ((y - VIS_H / 2) * m) / 24;
    for (x = 0; x < VIS_W; x++) {
      int sx = cx + ((x - VIS_W / 2) * m) / 24;
      uint8_t v = 0;
      if (sx >= 0 && sx < VIS_W && sy >= 0 && sy < VIS_H)
        v = img[sy * VIS_W + sx];
      canvas[y * VIS_W + x] = v;
    }
  }

  for (y = 0; y < VIS_GRID; y++) {
    for (x = 0; x < VIS_GRID; x++) {
      int32_t acc = (int32_t)canvas[(2 * y) * VIS_W + 2 * x] +
                    canvas[(2 * y) * VIS_W + 2 * x + 1] +
                    canvas[(2 * y + 1) * VIS_W + 2 * x] +
                    canvas[(2 * y + 1) * VIS_W + 2 * x + 1];
      out[y * VIS_GRID + x] = (int16_t)(acc / 4);
    }
  }

  for (i = 0; i < VIS_FEAT; i++) sum += out[i];
  sum /= VIS_FEAT;
  for (i = 0; i < VIS_FEAT; i++) {
    out[i] = (int16_t)(out[i] - sum);
    l1 += (out[i] < 0) ? -out[i] : out[i];
  }
  if (l1 == 0) return 0;
  for (i = 0; i < VIS_FEAT; i++)
    out[i] = (int16_t)(((int32_t)out[i] * 256) / l1);
  return 1;
}

void vision_init_prototypes(void)
{
  int c;
  uint8_t img[VIS_N];
  int16_t feat[VIS_FEAT];
  for (c = 0; c < VIS_CLASSES; c++) {
    int i;
    vision_render(c, img, VIS_W / 2, VIS_H / 2, 12, 0, 7u);
    if (!extract(img, feat)) {
      for (i = 0; i < VIS_FEAT; i++) feat[i] = 0;
    }
    for (i = 0; i < VIS_FEAT; i++) proto[c][i] = feat[i];
  }
}

int vision_classify(const uint8_t *img, int *dist_out)
{
  int16_t feat[VIS_FEAT];
  int best = VIS_UNKNOWN;
  int best_d = 1 << 30;
  int c, i;

  if (!extract(img, feat)) {
    if (dist_out) *dist_out = -1;
    return VIS_UNKNOWN;
  }

  for (c = 0; c < VIS_CLASSES; c++) {
    int d = 0;
    for (i = 0; i < VIS_FEAT; i++) {
      int v = (int)feat[i] - (int)proto[c][i];
      d += (v < 0) ? -v : v;
    }
    if (d < best_d) {
      best_d = d;
      best = c;
    }
  }

  /* Reject anything that does not look like one of the five prototypes. */
  if (best_d > 150) best = VIS_UNKNOWN;
  if (dist_out) *dist_out = best_d;
  return best;
}

void vision_dump(const uint8_t *img)
{
  int x, y;
  for (y = 0; y < VIS_H; y += 2) {
    for (x = 0; x < VIS_W; x += 2) {
      int v = img[y * VIS_W + x] + img[y * VIS_W + x + 1] +
              img[(y + 1) * VIS_W + x] + img[(y + 1) * VIS_W + x + 1];
      uart_putc(v > 400 ? '#' : (v > 120 ? '+' : '.'));
    }
    uart_putc('\n');
  }
}