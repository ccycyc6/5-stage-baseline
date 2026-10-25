#!/usr/bin/env python3
"""Flat firmware binary -> $readmemh image for the 128-bit on-chip memory.

Each output line is one 16-byte beat, printed as 32 hex digits with the first
byte of the beat in the least significant position (i.e. the word order the
128-bit memory port expects on a little-endian RISC-V core).
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()
if len(data) % 16:
    data += b'\0' * (16 - len(data) % 16)
with open(dst, 'w') as f:
    for i in range(0, len(data), 16):
        line = data[i:i + 16]
        # little endian: byte 0 -> bits [7:0]
        f.write(''.join('%02x' % line[15 - k] for k in range(16)) + '\n')
print('%s: %d bytes -> %s (%d lines)' % (src, len(data), dst, len(data) // 16))
