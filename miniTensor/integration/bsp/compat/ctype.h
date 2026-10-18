/* Minimal freestanding <ctype.h> for the MundusJyd BSP. */
#ifndef MT_COMPAT_CTYPE_H
#define MT_COMPAT_CTYPE_H

int isprint(int c);
int isspace(int c);
int isdigit(int c);
int isalpha(int c);
int isalnum(int c);
int isxdigit(int c);
int isupper(int c);
int islower(int c);
int tolower(int c);
int toupper(int c);

#endif
