#!/usr/bin/env python3
"""Write a binary file as one hex byte per line, for Verilator $readmemh."""
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
data = src.read_bytes()
dst.write_text("".join("%02x\n" % b for b in data), encoding="ascii")
print("bin2hex8: %s -> %s (%d bytes)" % (src, dst, len(data)))
