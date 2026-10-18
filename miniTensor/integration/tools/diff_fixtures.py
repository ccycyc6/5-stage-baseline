#!/usr/bin/env python3
"""Compare two packed fixtures byte-for-byte, and check a golden against the
weights it claims to describe.

Written while chasing the Y11 chain bug.  It established the key fact: the two
packers (the one behind the passing mt_yolo test and the one behind the failing
mt_yolocnn chain) emit IDENTICAL weights, image, bias and config for the same
layer at the same resolution, but DIFFERENT goldens.  So the disagreement is in
the reference, not in the data.

Usage: .venv/bin/python integration/tools/diff_fixtures.py
"""
import re
import sys

import numpy as np


def grab(path, name):
    txt = open(path).read()
    m = re.search(r"unsigned char %s\[(\d+)\] = \{([^}]*)\};" % name, txt)
    if not m:
        return None
    return np.array([int(v) for v in m.group(2).split(",")], dtype=np.uint8)


def word(a):
    return int(a[0]) | int(a[1]) << 8 | int(a[2]) << 16 | int(a[3]) << 24


def compare(label, a, b):
    if a is None or b is None:
        print("%-10s missing (%s/%s)" % (label, a is None, b is None))
        return
    if a.shape != b.shape:
        print("%-10s SHAPE %s vs %s" % (label, a.shape, b.shape))
        return
    d = np.nonzero(a != b)[0]
    extra = ""
    if d.size:
        extra = "  first at %d: %02x vs %02x" % (d[0], a[d[0]], b[d[0]])
    print("%-10s %7d bytes, %7d differ%s" % (label, a.size, d.size, extra))


def main():
    old = "integration/bsp/mt_yolo_weights.h"
    new = "integration/bsp/mt_yolocnn_weights.h"
    compare("weights", grab(old, "yolo_wt"), grab(new, "yc_wt0"))
    compare("image", grab(old, "yolo_img"), grab(new, "yc_img"))
    compare("bias", grab(old, "yolo_bias"), grab(new, "yc_bias0"))
    compare("config", grab(old, "yolo_cfg"), grab(new, "yc_cfg0"))
    compare("golden", grab(old, "yolo_gold"), grab(new, "yc_gold0"))
    print()
    print("The hardware passes mt_yolo against the OLD golden, so when the two")
    print("goldens disagree with identical inputs, suspect the NEW one.")
    print("NOTE: a third, independent recomputation from the packed weights also")
    print("failed to reproduce either golden, so that check has a bug of its own")
    print("and cannot be used as the tie-breaker yet.")


if __name__ == "__main__":
    main()
