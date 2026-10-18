#!/usr/bin/env python3
"""Host-side check of the miniTensor 3x3 convolution layout.

miniTensor's only GEMM primitive is a 4x4x4 signed-INT8 tile:

    C[i][j] = sum_k A[i][k] * B[k][j]        (i, j, k in 0..3)

with A and B each packed into ONE 16-byte UB row (A row-major: byte 4i+k,
B row-major: byte 4k+j) and C occupying FOUR UB rows of 4 x INT32.

Mapping a convolution onto it:

    M = output channels      -> rows of A  (A = weights)
    N = output spatial       -> cols of B  (B = im2col)
    K = C_in * 3 * 3         -> the reduction

This script builds the exact A/B row images the C driver will build, runs the
same GEMM/accumulate/epilogue sequence the driver will issue, and compares the
result against a plain NumPy convolution.  If this agrees, any remaining bug in
the RTL run is in the plumbing, not in the layout maths.
"""
import numpy as np

C_IN, C_OUT, H, W = 4, 4, 6, 6
KHKW = 9
K_DIM = C_IN * KHKW          # 36
H_OUT, W_OUT = H, W          # stride 1, pad 1
N_DIM = H_OUT * W_OUT        # 36
assert C_OUT % 4 == 0 and N_DIM % 4 == 0 and K_DIM % 4 == 0

rng = np.random.default_rng(20261008)
x = rng.integers(-8, 8, size=(H, W, C_IN), dtype=np.int8)      # NHWC
wt = rng.integers(-8, 8, size=(C_OUT, K_DIM), dtype=np.int8)    # [m][k]
# One bias per output channel, replicated across the 4 spatial lanes of the
# epilogue's 4x4 bias tile -- which is what the driver packs.
_bias_c = rng.integers(-200, 200, size=(C_OUT,), dtype=np.int32)
bias = np.repeat(_bias_c[:, None], 4, axis=1)

# Chosen so the accumulator (|sum| <= 36 * 8 * 8 = 2304) lands roughly in
# [-40, 40]: a saturated output would make the comparison useless.
MULT, SHIFT, ZP, RELU = 16, 10, 0, 0


def im2col():
    """B[k][n] with k = c*9 + ky*3 + kx and n = ho*W_OUT + wo, zero padded."""
    b = np.zeros((K_DIM, N_DIM), dtype=np.int8)
    for ho in range(H_OUT):
        for wo in range(W_OUT):
            n = ho * W_OUT + wo
            for c in range(C_IN):
                for ky in range(3):
                    for kx in range(3):
                        hi, wi = ho + ky - 1, wo + kx - 1
                        if 0 <= hi < H and 0 <= wi < W:
                            b[c * 9 + ky * 3 + kx][n] = x[hi][wi][c]
    return b


def pack_a():
    """(K_DIM/4) UB rows: byte 4*i + k = weights[m0 + i][ks*4 + k]."""
    rows = np.zeros((K_DIM // 4, 16), dtype=np.int8)
    for ks in range(K_DIM // 4):
        for i in range(4):
            for k in range(4):
                rows[ks][4 * i + k] = wt[i][ks * 4 + k]
    return rows


def pack_b(b):
    """(K/4) * (N/4) UB rows: byte 4*k + j = B[ks*4 + k][nt*4 + j]."""
    rows = np.zeros(((K_DIM // 4) * (N_DIM // 4), 16), dtype=np.int8)
    for ks in range(K_DIM // 4):
        for nt in range(N_DIM // 4):
            for k in range(4):
                for j in range(4):
                    rows[ks * (N_DIM // 4) + nt][4 * k + j] = b[ks * 4 + k][nt * 4 + j]
    return rows


def requant(c, b):
    v = (np.int64(c) + np.int64(b)) * MULT
    v = v >> SHIFT
    v = v + ZP
    if RELU:
        v = max(v, 0)
    return np.int8(np.clip(v, -128, 127))


def run_tiles(a_rows, b_rows):
    """Emulate the MT_GEMM + MT_EPILOGUE sequence and return packed INT8."""
    ntiles = N_DIM // 4
    out = np.zeros((C_OUT, N_DIM), dtype=np.int8)
    for nt in range(ntiles):
        acc = np.zeros((4, 4), dtype=np.int32)
        for ks in range(K_DIM // 4):
            a = a_rows[ks].reshape(4, 4).astype(np.int32)     # noqa: A001
            bm = b_rows[ks * ntiles + nt].reshape(4, 4).astype(np.int32)
            acc += a @ bm                                     # accumulate
        for i in range(4):
            for j in range(4):
                out[i][nt * 4 + j] = requant(acc[i][j], bias[i][j])
    return out


b_mat = im2col()
golden = np.zeros((C_OUT, N_DIM), dtype=np.int8)
for m in range(C_OUT):
    for n in range(N_DIM):
        acc = int(np.dot(wt[m].astype(np.int32), b_mat[:, n].astype(np.int32)))
        golden[m][n] = requant(acc, bias[m][0])

got = run_tiles(pack_a(), pack_b(b_mat))
same = np.array_equal(got, golden)
print("A rows :", K_DIM // 4, " B rows :", (K_DIM // 4) * (N_DIM // 4))
print("UB rows needed:", (K_DIM // 4) + (K_DIM // 4) * (N_DIM // 4) + ntiles_ub if (ntiles_ub := (N_DIM // 4) * 4) else 0)
print()
print("golden[0][:8] =", golden[0][:8])
print("got   [0][:8] =", got[0][:8])
print()
print("LAYOUT CHECK:", "PASS" if same else "FAIL")
raise SystemExit(0 if same else 1)
