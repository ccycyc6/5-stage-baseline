#!/usr/bin/env python3
"""Run a multi-layer slice of a REAL YOLO model on miniTensor.

Takes convolutions #0, #1 and #2 in graph order out of tiny-yolov3.onnx -- that
is layers 0, 2 and 4 of the network, the first three stages of the backbone --
folds each one's BatchNormalization, quantises, and packs them as a chain:

    x -> conv3x3(3->16)+leaky -> maxpool -> conv3x3(16->32)+leaky
      -> maxpool -> conv3x3(32->64)+leaky

Every stage's integer output is emitted as a golden, so a mismatch is
attributable to one layer rather than to the chain.  The only workaround is the
3-channel input, zero-padded to 4 because MT_GEMM needs multiples of 4; the
activations are the model's real LeakyReLU(0.1).

Writes integration/bsp/mt_yolocnn_weights.h.
"""
import sys

import numpy as np
import onnx

import pack_weights as P

RES = int(__import__("os").environ.get("YC_RES", "16"))  # -> RES/2 -> RES/4
ALPHA = 0.1
SHIFT = 14
SEED = 0x13579BDF


def load_convs(path, which):
    """Return the requested convolutions in graph order, BN folded."""
    g = onnx.load(path).graph
    init = {i.name: onnx.numpy_helper.to_array(i) for i in g.initializer}
    out, seen = [], 0
    for node in g.node:
        if node.op_type != "Conv":
            continue
        if seen in which:
            w = init[node.input[1]]
            b = init[node.input[2]] if len(node.input) > 2 and node.input[2] in init \
                else np.zeros(w.shape[0], np.float32)
            for c in g.node:
                if c.op_type == "BatchNormalization" and c.input[0] == node.output[0]:
                    sc, bb = init[c.input[1]], init[c.input[2]]
                    mu, va = init[c.input[3]], init[c.input[4]]
                    k = sc / np.sqrt(va + 1e-5)
                    w = (w * k.reshape(-1, 1, 1, 1)).astype(np.float32)
                    b = (b * k + (bb - mu * k)).astype(np.float32)
            out.append((seen, w, b))
        seen += 1
    return out


def conv_acc(x_ghwc, wq, cin_p, cout, k):
    """Exact integer accumulator (without bias), mirroring net_conv.

    Runs over the activation's ALLOCATED width, padding columns hold zeros, so
    the result matches the hardware's padded row stride.  net_pad zero-fills
    outside the logical width, and the array's padding columns are zero too.
    """
    ng, h, w, _ = x_ghwc.shape
    xh = x_ghwc.transpose(1, 2, 0, 3).reshape(h, w, cin_p)
    pad = np.zeros((h + 2, w + 2, cin_p), np.int64)
    pad[1:1 + h, 1:1 + w, :] = xh
    acc = np.zeros((h, w, cout), np.int64)
    for ky in range(k):
        for kx in range(k):
            acc += np.einsum('hwc,oc->hwo', pad[ky:ky + h, kx:kx + w, :],
                             wq[:, :, ky, kx].astype(np.int64))
    return acc


def pool_mem(mem, res, cout, dw):
    """Signed 2x2 max pool in [g][h][w][4] order (matches net_pool2).

    Returns a 4-D int array, which is what the next conv consumes; the flat
    uint8 form is only needed for the golden tables.
    """
    ng = cout // 4
    a = P.signed8(mem).reshape(ng, res, res, 4)
    a = a.reshape(ng, res // 2, 2, res // 2, 2, 4).max(axis=(2, 4))
    if dw > res // 2:
        b = np.zeros((ng, res // 2, dw, 4), np.int64)
        b[:, :, :res // 2, :] = a
        a = b
    return a


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "models/tiny-yolov3.onnx"
    convs = load_convs(path, {0, 1, 2})
    print("real backbone slice: convs #0,#1,#2 = layers 0,2,4 of tiny-yolov3")

    rng = np.random.default_rng(SEED)
    res = RES
    xmem = np.zeros((1, res, res, 4), np.int32)
    xmem[0, :, :, :3] = np.clip(
        np.round(rng.integers(0, 256, size=(res, res, 3)) / 255.0 * 127.0),
        -128, 127)
    img_mem = (xmem.reshape(-1) & 0xFF).astype(np.uint8)

    blocks, golds, sizes = [], [], []
    cur, cur_cin = xmem, 4
    for li, (idx, w, b) in enumerate(convs):
        cout, cin, kh, kw = w.shape
        # Only the stem may differ: its 3 channels are zero-padded up to 4.
        assert cin == cur_cin or (li == 0 and cin < cur_cin), \
            "chain mismatch at conv %d: %d vs %d" % (idx, cin, cur_cin)
        wp = np.zeros((cout, cur_cin, kh, kw), np.float32)
        wp[:, :cin] = w
        wq, _ = P.quant(wp)
        bq = np.round(b).astype(np.int32)
        # The layer's own width, rounded up to a multiple of 4.  net_conv can
        # only tile 4 pixels at a time, so a 6-wide output is computed at 8 and
        # the consumer reads the first 6.
        wpad = ((res + 3) // 4) * 4
        if cur.shape[2] < wpad:
            z = np.zeros((cur.shape[0], cur.shape[1], wpad, 4), np.int64)
            z[:, :, :cur.shape[2], :] = cur
            cur = z
        acc = conv_acc(cur, wq, cur_cin, cout, kh)
        tot = acc + bq[None, None, :]
        s_acc = max(1e-9, float(np.max(np.abs(tot))) / 127.0)
        mult = max(1, min(32767, int(round((1 << SHIFT) / s_acc))))
        mult2 = max(1, min(32767, int(round(mult * ALPHA))))
        v1 = tot * mult >> SHIFT
        v2 = tot * mult2 >> SHIFT
        q = np.clip(np.maximum(v1, v2), -128, 127)
        L = dict(h=res, w=res, c_in=cur_cin, c_out=cout, k=kh, pad=1, relu=0)
        nmt = P.choose_nmt(L)
        wt, bias, cfg16 = P.to_rows(wq, L, mult, SHIFT, bq, 0, 0, nmt)
        cfg = np.zeros(32, np.uint8)
        cfg[0:16] = cfg16
        cfg[16:20] = np.frombuffer(
            np.uint32((mult2 & 0xFFFF) | ((SHIFT & 0x1F) << 16)).tobytes(),
            dtype=np.uint8)
        # to_mem() is NOT optional: q is [h][w][c] and the hardware writes
        # [g][h][w][4].  Skipping the reorder leaves the first 4 bytes of the
        # first pixel coincidentally correct and everything else wrong, which
        # looks exactly like a hardware A-row fault and cost two rounds of
        # hunting a bug that was in this line.
        mem = P.to_mem(q)
        golds.append(mem)
        sizes.append((res, wpad, cout))
        # For the first convolution also keep the pre-LeakyReLU requant, so the
        # firmware can tell a convolution error from a vector-path error.
        if li == 0:
            plain0 = np.clip(v1, -128, 127)
            plain_mem = P.to_mem(plain0)
        print("  conv#%d %d->%d %dx%d (wpad %d) nmt=%d rows=%d mult=%d a*mult=%d a-path=%.0f%%"
              % (idx, cin, cout, res, res, wpad, nmt,
                 (cur_cin // 4) * kh * kw * (cout // 4), mult, mult2,
                 100.0 * float(np.mean(v1 < 0))))
        blocks.append((wt, bias, cfg))
        cur_cin = cout
        if li < len(convs) - 1:
            res //= 2
            dw = ((res + 3) // 4) * 4
            cur = pool_mem(mem, res * 2, cout, dw)
            wpad = dw

    # Serialise the weight blob: [wt][bias][cfg] per layer, in layer order.
    blob = bytearray()
    blob_off = []
    for wt, bias, cfg in blocks:
        ow = len(blob)
        blob += np.ascontiguousarray(wt).tobytes()
        ob = len(blob)
        blob += np.ascontiguousarray(bias).tobytes()
        oc = len(blob)
        blob += np.ascontiguousarray(cfg).tobytes()
        blob_off.append((ow, ob, oc))
    with open("models/yc_weights.bin", "wb") as bf:
        bf.write(bytes(blob))
    print("  wrote models/yc_weights.bin (%d bytes)" % len(blob))

    def carr(name, data):
        body = ",".join(str(int(v)) for v in np.asarray(data).reshape(-1))
        return "static const unsigned char %s[%d] = {%s};\n" % \
               (name, np.asarray(data).size, body)

    with open("integration/bsp/mt_yolocnn_weights.h", "w") as f:
        f.write("/* Auto-generated by integration/tools/pack_real.py."
                "  DO NOT EDIT. */\n")
        f.write("#ifndef MT_YOLOCNN_WEIGHTS_H\n#define MT_YOLOCNN_WEIGHTS_H\n\n")
        f.write("#define YC_RES0 %d\n" % RES)
        for i, (r, wp, c) in enumerate(sizes):
            f.write("#define YC_RES%d %d\n#define YC_WP%d %d\n#define YC_COUT%d %d\n"
                    % (i, r, i, wp, i, c))
        f.write("#define YC_LAYERS %d\n\n" % len(convs))
        # Weights, biases and configs go to a separate blob linked into the
        # uncached extension window, not into .rodata: a full model's weights do
        # not fit in the 192 KiB of DRAM.  Only offsets and lengths live here.
        f.write("#define YC_BLOB_BASE 0x80400000u\n")
        for i, (ow, ob, oc) in enumerate(blob_off):
            f.write("#define YC_BLOB_WT%d   %du\n" % (i, ow))
            f.write("#define YC_BLOB_BIAS%d %du\n" % (i, ob))
            f.write("#define YC_BLOB_CFG%d  %du\n" % (i, oc))
            f.write("#define YC_WT_LEN%d    %du\n" % (i, blocks[i][0].size))
            f.write("#define YC_BIAS_LEN%d  %du\n" % (i, blocks[i][1].size))
            f.write("#define YC_CFG_LEN%d   %du\n" % (i, blocks[i][2].size))
        f.write("\n")
        f.write(carr("yc_img", img_mem))
        for i, g in enumerate(golds):
            f.write(carr("yc_gold%d" % i, g))
        f.write(carr("yc_gold0_plain", plain_mem))
        f.write("\n#endif\n")
    tot = sum(a.size for a in golds) + len(img_mem) + \
        sum(w.size + b.size + c.size for w, b, c in blocks)
    print("  wrote integration/bsp/mt_yolocnn_weights.h (%d bytes of tables)" % tot)


if __name__ == "__main__":
    main()
