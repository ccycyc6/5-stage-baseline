#!/usr/bin/env python3
import sys, struct
src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()
if len(data) % 4:
    data += b'\0' * (4 - len(data) % 4)
with open(dst, 'w') as f:
    for i in range(0, len(data), 4):
        w = struct.unpack_from('<I', data, i)[0]
        f.write(f'{w:08x}\n')
print(f'{src}: {len(data)} bytes -> {dst}')
