/* Minimal freestanding <stdio.h> for the MundusJyd BSP.
 *
 * The firmware links with -nostdlib and only needs declarations: FinSH pulls
 * <stdio.h> in unconditionally, and the few symbols actually referenced are
 * satisfied by the BSP's own runtime or removed by --gc-sections.
 * Needed because the available riscv64-unknown-elf toolchain ships without
 * newlib headers. */
#ifndef MT_COMPAT_STDIO_H
#define MT_COMPAT_STDIO_H

#include <stddef.h>
#include <stdarg.h>

int putchar(int c);
int printf(const char *format, ...);
int sprintf(char *buffer, const char *format, ...);
int snprintf(char *buffer, size_t count, const char *format, ...);
int vsnprintf(char *buffer, size_t count, const char *format, va_list args);

#endif
