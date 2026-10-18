#!/usr/bin/env python3
"""Golden data for the residual-block test (mt_res).

Builds a basic ResNet/CSPDarknet bottleneck core on an 8x8x16 map:

    y = relu( conv3x3( relu(conv3x3(x)) ) + x )

The first convolution runs with ReLU in its epilogue; the second runs without,
because the residual add comes after it and the final ReLU is applied once, to
the sum.  The add is the VPU's ADD8 in the UB, not a CPU pass, so this exercises
the MT_VECTOR path in a real network for the first time.

Writes integration/bsp/mt_res_weights.h.
"""
import numpy as np

import pack_weights as P

H = W = 8
C = 16
K = 3
PAD = 1
MULT = 1
SHIFT = 4    # large enough that the residual sum can saturate int8, so the
             # ADD8 saturation behaviour is actually exercised
SEED = 0x2468ACE0


def lcg_bytes(n, seed=SEED):
    out = np.zeros(n, dtype=np.uint8)
    s = seed
    for i in range(n):
        s = (s * 1103515245 + 12345) & 0xFFFFFFFF
        out[i] = (s >> 16) & 0xFF
    return out


def main():
    L = dict(h=H, w=W, c_in=C, c_out=C, k=K, pad=PAD, relu=1)
    ng, nm = C // 4, C // 4
    ntap = ng * K * K
    nmt = P.choose_nmt(L)
    print("residual block: 8x8x%d, two 3x3 convs, %d weight rows each, nmt=%d"
          % (C, ng * K * K * nm, nmt))

    def mk(seed):
        raw = lcg_bytes(C * C * K * K, seed).astype(np.int32)
        return ((raw % 5) - 2).reshape(C, C, K, K)

    w1, w2 = mk(SEED), mk(SEED ^ 0x5A5A5A5A)
    araw = (lcg_bytes(H * W * C, SEED ^ 0x1234).astype(np.int32) % 255) - 127
    aq = araw.reshape(H, W, ng, 4).transpose(2, 0, 1, 3)     # [g][h][w][c]
    img_mem = aq.reshape(-1)

    bias_q = np.zeros(C, dtype=np.int32)
    blocks = []
    for li, (wq, relu) in enumerate(((w1, 1), (w2, 0))):
        wt, bias, cfg = P.to_rows(wq, L, MULT, SHIFT, bias_q, 0, relu, nmt)
        blocks.append((wt, bias, cfg))
        print("  conv%d: %d weight bytes, relu=%d" % (li + 1, wt.size, relu))

    def conv_ref(x_ghwc, rows, relu):
        """Integer reference for one 3x3 conv, mirroring net_conv.

        x_ghwc is the activation in the hardware's [g][h][w][4] memory order.
        """
        ngx = C // 4
        pad = np.zeros((ngx, H + 2 * PAD + K, W + 2 * PAD, 4), dtype=np.int32)
        pad[:, PAD:PAD + H, PAD:PAD + W, :] = x_ghwc
        out = np.zeros((H, W, C), dtype=np.int64)
        for ti in range((nm + nmt - 1) // nmt):
            mg0 = ti * nmt
            for ky in range(K):
                for kx in range(K):
                    for g in range(ngx):
                        q = (g * K * K) + (ky * K) + kx
                        for t in range(W // 4):
                            arow = pad[g, ky:ky + H, t * 4 + kx:t * 4 + kx + 4, :]
                            for j in range(min(nmt, nm - mg0)):
                                row = (ti * ntap * nmt) + (q * nmt) + j
                                Bs = P.signed8(rows[row].reshape(4, 4))
                                for r in range(H):
                                    out[r, t * 4:t * 4 + 4,
                                        (mg0 + j) * 4:(mg0 + j) * 4 + 4] += \
                                        arow[r] @ Bs
        v = out >> SHIFT
        if relu:
            v = np.maximum(v, 0)
        return np.clip(v, -128, 127)

    h1 = conv_ref(aq, blocks[0][0].reshape(-1, 16), True)          # [h][w][c]
    gold_h1 = P.to_mem(h1)
    h1g = h1.reshape(H, W, ng, 4).transpose(2, 0, 1, 3)            # [g][h][w][c]
    h2 = conv_ref(h1g, blocks[1][0].reshape(-1, 16), False)
    gold_h2 = P.to_mem(h2)
    # The skip is the BLOCK INPUT x, not the intermediate h1: the block is
    #     y = relu(conv2(relu(conv1(x))) + x)
    # which is what the firmware's skip_off = RES_IMG selects.  (Getting this
    # wrong is easy -- x and h1 have the same shape -- and it produced a
    # plausible-looking golden that disagreed with the hardware everywhere.)
    x_hwc = aq.transpose(1, 2, 0, 3).reshape(H, W, C)
    #
    # The residual add is the VPU's ADD8, which WRAPS rather than saturating
    # (vpu_vector_alu.sv:22 is a plain 8-bit add).  This is a real constraint on
    # residual connections: a skip branch has to be scaled so the sum stays in
    # range, because overflow silently folds the sign instead of clamping.
    s = x_hwc + h2
    y = ((s + 128) % 256) - 128           # two's-complement wrap, as ADD8 does
    y = np.maximum(y, 0)                  # final ReLU, via VPU RELU8
    gold = P.to_mem(y)

    n_wrap = int(np.count_nonzero(np.abs(s) > 127))
    print("  skip = block input x; ADD8 wrapped on %d of %d values"
          % (n_wrap, s.size))
    print("  golden: %d bytes, range [%d, %d]"
          % (gold.size, int(y.min()), int(y.max())))

    def carr(name, data):
        body = ",".join(str(int(x)) for x in np.asarray(data).reshape(-1))
        return "static const unsigned char %s[%d] = {%s};\n" % \
               (name, np.asarray(data).size, body)

    with open("integration/bsp/mt_res_weights.h", "w") as f:
        f.write("/* Auto-generated by integration/tools/pack_res.py."
                "  DO NOT EDIT. */\n")
        f.write("#ifndef MT_RES_WEIGHTS_H\n#define MT_RES_WEIGHTS_H\n\n")
        f.write("#define RES_H %d\n#define RES_W %d\n#define RES_C %d\n"
                % (H, W, C))
        f.write("#define RES_OUT_BYTES %d\n\n" % gold.size)
        for i, (wt, bias, cfg) in enumerate(blocks):
            f.write(carr("res_wt%d" % (i + 1), wt))
            f.write(carr("res_bias%d" % (i + 1), bias))
            f.write(carr("res_cfg%d" % (i + 1), cfg))
        f.write(carr("res_img", (img_mem.astype(np.int32) & 0xFF).astype(np.uint8)))
        f.write(carr("res_gold", gold))
        f.write(carr("res_gold_h1", gold_h1))
        f.write(carr("res_gold_h2", gold_h2))
        f.write("\n#endif\n")
    print("  wrote integration/bsp/mt_res_weights.h")


if __name__ == "__main__":
    main()
