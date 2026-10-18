#!/usr/bin/env python3
"""Golden data for the wide-layer weight-streaming test (mt_wide).

Builds a single 3x3 convolution with 48 input and 48 output channels over an
8x8 map.  That layer needs ng*k*k*nm = 12*9*12 = 1296 weight rows (20736 bytes),
which is 9x what UB_WT can hold (144 rows), so net_conv must reload the weights
per output-group tile -- exactly the situation a real YOLO layer is in.

The reference is the same integer model the RTL implements, so the firmware
comparison is bit-exact rather than tolerance based.

Writes integration/bsp/mt_wide_weights.h.
"""
import numpy as np

import pack_weights as P

import sys

# Geometry is overridable so the layer can be shrunk to bisect a failure:
#   python3 pack_wide.py <H> <c_in> <c_out> <k>
H = W = int(sys.argv[1]) if len(sys.argv) > 1 else 8
C_IN = int(sys.argv[2]) if len(sys.argv) > 2 else 48
C_OUT = int(sys.argv[3]) if len(sys.argv) > 3 else 48
K = int(sys.argv[4]) if len(sys.argv) > 4 else 3
PAD = K // 2
MULT = 1
# Chosen so the accumulator lands in a wide, discriminating range rather than
# collapsing to a couple of small values.
SHIFT = 7
SEED = 0x13579BDF


def lcg_bytes(n, seed=SEED):
    """Same LCG the firmware uses, so both sides agree without sharing a table."""
    out = np.zeros(n, dtype=np.uint8)
    s = seed
    for i in range(n):
        s = (s * 1103515245 + 12345) & 0xFFFFFFFF
        out[i] = (s >> 16) & 0xFF
    return out


def main():
    L = dict(h=H, w=W, c_in=C_IN, c_out=C_OUT, k=K, pad=PAD, relu=1)
    nmt = P.choose_nmt(L)
    ng, nm = C_IN // 4, C_OUT // 4
    ntap = ng * K * K
    print("wide layer: c_in=%d c_out=%d k=%d -> %d weight rows (%d bytes)"
          % (C_IN, C_OUT, K, ng * K * K * nm, ng * K * K * nm * 16))
    print("  UB_WT capacity %d rows -> nmt=%d, %d tiles"
          % (144, nmt, (nm + nmt - 1) // nmt))

    # Weights: small signed values so the layer does not simply saturate.
    raw = lcg_bytes(C_OUT * C_IN * K * K).view(np.int8).astype(np.int32)
    wq = (raw % 5) - 2                       # [-2, 2]
    wq = wq.reshape(C_OUT, C_IN, K, K).astype(np.int32)

    # Activations: signed int8.
    araw = ((lcg_bytes(H * W * C_IN).astype(np.int32) % 255) - 127)  # [-127, 127]
    aq = araw.reshape(H, W, ng, 4).transpose(2, 0, 1, 3)   # [g][h][w][c]
    img_mem = aq.reshape(-1)                                # the memory order

    bias_q = np.zeros(C_OUT, dtype=np.int32)
    wt, bias, cfg = P.to_rows(wq, L, MULT, SHIFT, bias_q, 0, 0, nmt)   # relu off
    print("  packed: %d weight bytes, %d bias bytes, nmt=%d"
          % (wt.size, bias.size, cfg[4]))
    # Checksums the firmware recomputes over the staged buffer, so a staging
    # or offset error is distinguishable from an accelerator error.
    print("  wt checksum: all=%08x lane0=%08x tile8lane0=%08x"
          % (int(wt.astype(np.uint32).sum()) & 0xFFFFFFFF,
             int(wt.reshape(-1, 16)[:, 0].astype(np.uint32).sum()) & 0xFFFFFFFF,
             int(wt.reshape(-1, 16)[8 * 108:9 * 108, 0].astype(np.uint32).sum())
             & 0xFFFFFFFF))
    print("  img checksum: %08x"
          % (int(np.frombuffer(img_mem.astype(np.uint8).tobytes(),
                               dtype=np.uint8).astype(np.uint32).sum()) & 0xFFFFFFFF))

    # Integer reference, mirroring net_conv: A is the activation row (4 spatial
    # x 4 input channels), B the weight row (4 input x 4 output channels).
    # Out-of-range taps read 0, matching net_pad (it zero-fills, not edge-fills).
    pad = np.zeros((ng, H + 2 * PAD + K, W + 2 * PAD, 4), dtype=np.int32)
    pad[:, PAD:PAD + H, PAD:PAD + W, :] = aq
    out = np.zeros((H, W, C_OUT), dtype=np.int64)
    wt_rows = wt.reshape(-1, 16)
    for mt in range(0, nm, nmt):
        ti = mt // nmt
        njt = min(nmt, nm - mt)
        for ky in range(K):
            for kx in range(K):
                for g in range(ng):
                    q = (g * K * K) + (ky * K) + kx
                    for t in range(W // 4):
                        arow = pad[g, ky:ky + H, t * 4 + kx:t * 4 + kx + 4, :]
                        for j in range(njt):
                            row = (ti * ntap * nmt) + (q * nmt) + j
                            Bs = P.signed8(wt_rows[row].reshape(4, 4))
                            for r in range(H):
                                # arow[r] is the 4x4 A tile for output row r
                                acc = arow[r] @ Bs          # [4 spatial][4 out]
                                out[r, t * 4:t * 4 + 4,
                                    (mt + j) * 4:(mt + j) * 4 + 4] += acc

    v = (out + bias_q[None, None, :]) * MULT
    v = v >> SHIFT
    v = np.clip(v, -128, 127)
    gold = P.to_mem(v)                        # [g][h][w][4] memory order
    print("  golden output: %d bytes, range [%d, %d]"
          % (gold.size, int(v.min()), int(v.max())))
    # Raw accumulators for the elements that disagree, so the firmware value can
    # be compared against the un-requantised arithmetic.
    print("  raw acc grp8 (h0,w0,c0)=%d (h0,w4,c0)=%d"
          % (int(out[0, 0, 32]), int(out[0, 4, 32])))

    def carr(name, data):
        body = ",".join(str(int(x)) for x in np.asarray(data).reshape(-1))
        return "static const unsigned char %s[%d] = {%s};\n" % \
               (name, np.asarray(data).size, body)

    with open("integration/bsp/mt_wide_weights.h", "w") as f:
        f.write("/* Auto-generated by integration/tools/pack_wide.py."
                "  DO NOT EDIT. */\n")
        f.write("#ifndef MT_WIDE_WEIGHTS_H\n#define MT_WIDE_WEIGHTS_H\n\n")
        f.write("#define WIDE_H %d\n#define WIDE_W %d\n" % (H, W))
        f.write("#define WIDE_C_IN %d\n#define WIDE_C_OUT %d\n" % (C_IN, C_OUT))
        f.write("#define WIDE_OUT_BYTES %d\n\n" % gold.size)
        f.write(carr("wide_wt", wt))
        f.write(carr("wide_bias", bias))
        f.write(carr("wide_cfg", cfg))
        f.write(carr("wide_img", (img_mem.astype(np.int32) & 0xFF).astype(np.uint8)))
        f.write(carr("wide_gold", gold))
        f.write("\n#endif\n")
    print("  wrote integration/bsp/mt_wide_weights.h")


if __name__ == "__main__":
    main()
