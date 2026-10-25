#ifndef ARES_VISION_H
#define ARES_VISION_H

#include "board.h"

/* 32x32 8-bit grayscale frame, the same size the camera/preview path uses. */
#define VIS_W        32
#define VIS_H        32
#define VIS_N        (VIS_W * VIS_H)
#define VIS_GRID     16              /* classifier works on a 16x16 resample */
#define VIS_FEAT     (VIS_GRID * VIS_GRID)
#define VIS_CLASSES  5

#define VIS_UNKNOWN  (-1)

/* Shape classes, in prototype order. */
enum {
  VIS_CIRCLE = 0,
  VIS_SQUARE,
  VIS_TRIANGLE,
  VIS_CROSS,
  VIS_RING
};

extern const char *const vision_class_name[VIS_CLASSES];

/* Render one synthetic "photo" of a class (used for the self test). */
void vision_render(int cls, uint8_t *img, int cx, int cy, int r,
                   int noise, uint32_t seed);

void vision_init_prototypes(void);

/* Classify a 32x32 image; returns class index, VIS_UNKNOWN, and writes the
 * best distance (lower is better) to *dist. */
int vision_classify(const uint8_t *img, int *dist);

/* Human readable 16x16 preview of a frame. */
void vision_dump(const uint8_t *img);

/* UART helpers (non-blocking receive). */
int  vis_getc(void);
int  vis_getc_timeout(int ticks);


#endif