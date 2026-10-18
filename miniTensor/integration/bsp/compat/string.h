/* Minimal freestanding <string.h> for the MundusJyd BSP.
 *
 * finsh_compat.c provides the definitions of the memory/string helpers the
 * firmware actually uses. */
#ifndef MT_COMPAT_STRING_H
#define MT_COMPAT_STRING_H

#include <stddef.h>

void  *memcpy(void *destination, const void *source, size_t count);
void  *memset(void *destination, int value, size_t count);
int    memcmp(const void *left, const void *right, size_t count);

size_t strlen(const char *text);
int    strcmp(const char *left, const char *right);
int    strncmp(const char *left, const char *right, size_t count);
char  *strcpy(char *destination, const char *source);
char  *strncpy(char *destination, const char *source, size_t count);
char  *strcat(char *destination, const char *source);
char  *strchr(const char *text, int character);

#endif
