#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stdint.h>
#include <stddef.h>

/* ARES-P4 bare-metal CoreMark port.  Board builds pass -DCPU_HZ=<hz>. */
#ifndef CPU_HZ
#define CPU_HZ              100000000u
#endif

#ifndef ITERATIONS
#define ITERATIONS          200
#endif

#define HAS_FLOAT           1
#define HAS_TIME_H          0
#define USE_CLOCK           0
#define HAS_STDIO           0
#define HAS_PRINTF          1

#define SEED_METHOD         SEED_VOLATILE
#define MEM_METHOD          MEM_STATIC
#define MULTITHREAD         1
#define MAIN_HAS_NOARGC     1
#define MAIN_HAS_NORETURN   0

#define COMPILER_VERSION    "GCC " __VERSION__
#define COMPILER_FLAGS      "-O2 -march=rv32im"
#define MEM_LOCATION        "DDR static"

typedef signed short        ee_s16;
typedef unsigned short      ee_u16;
typedef signed int          ee_s32;
typedef unsigned int        ee_u32;
typedef double              ee_f32;
typedef unsigned char       ee_u8;
typedef unsigned int        ee_ptr_int;
typedef size_t              ee_size_t;

typedef unsigned long long  CORE_TICKS;

#define align_mem(x) (void *)(4 + (((unsigned long)(x) - 1) & ~3))

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
  ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#define ioe_init() ((void)0)
int printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE==1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE==2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

#endif