/* Minimal freestanding <stdlib.h> for the MundusJyd BSP. */
#ifndef MT_COMPAT_STDLIB_H
#define MT_COMPAT_STDLIB_H

#include <stddef.h>

void *malloc(size_t size);
void *calloc(size_t count, size_t size);
void *realloc(void *pointer, size_t size);
void free(void *pointer);

int atoi(const char *text);
long strtol(const char *text, char **end, int base);
unsigned long strtoul(const char *text, char **end, int base);

void abort(void);
void exit(int status);

#endif
