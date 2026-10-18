#!/usr/bin/env python3
"""Run five real tiny-yolov3 stages on miniTensor, with a scheduler.

Layers 0, 2, 4, 6 and 8 of the network -- the first five convolutions of the
CSPDarknet backbone -- chained through the four 2x2/2 max pools between them,
with the model's real trained weights (BatchNormalization folded) and its real
LeakyReLU(0.1).

    x -> conv3x3(3->16)+leaky  -> pool -> conv3x3(16->32)+leaky
      -> pool -> conv3x3(32->64)+leaky -> pool -> conv3x3(64->128)+leaky
      -> pool -> conv3x3(128->256)+leaky

Run at 64x64 so the whole thing simulates in a few minutes.  Note this is NOT a
detector at that size -- the model was trained at 416x416 -- the point is that
the model's layer stack executes correctly and can be checked bit for bit.

The activations do not fit in the 64 KiB scratch (the stem alone is 64 KiB and
its padding buffer is another 50 KiB), so the buffers live in the uncached
extension window and the weights are read straight out of the blob there.

Writes models/ym_weights.bin and integration/bsp/mt_yolomodel_weights.h.
"""
import sys

import numpy as np
import onnx

import pack_weights as P

RES = 64
ALPHA = 0.1
SHIFT = 14
SEED = 0x13579BDF
WHICH = (0, 1, 2, 3, 4)          # graph-order convolution indices

# Everything -- weight blob, input, activations, goldens -- is addressed
# relative to ONE base, the start of the blob in the uncached extension window.
# That is deliberate: a layer can then read its weights straight out of the blob
# with no staging copy at all, because the accelerator's DMA reaches the same
# memory the CPU does.  The buffers sit past the blob.
BLOB_BASE = 0x80C00000
PAD_OFF = 0x0F0000                       # 52 KiB of padding scratch
OUT_OFF = [0x100000, 0x110000, 0x118000, 0x11C000, 0x11E000]


def load_convs(path, which):
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
            act = "none"
            for c in g.node:
                if c.op_type == "BatchNormalization" and c.input[0] == node.output[0]:
                    sc, bb = init[c.input[1]], init[c.input[2]]
                    mu, va = init[c.input[3]], init[c.input[4]]
                    k = sc / np.sqrt(va + 1e-5)
                    w = (w * k.reshape(-1, 1, 1, 1)).astype(np.float32)
                    b = (b * k + (bb - mu * k)).astype(np.float32)
                    for d in g.node:
                        if d.op_type in ("LeakyRelu", "Relu") and d.input[0] == c.output[0]:
                            act = d.op_type
            out.append((seen, w, b, act))
        seen += 1
    return out


def conv_acc(x_ghwc, wq, cin_p, cout, k):
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


def pool_mem(mem, h, w, cout):
    ng = cout // 4
    a = P.signed8(mem).reshape(ng, h, w, 4)
    return a.reshape(ng, h // 2, 2, w // 2, 2, 4).max(axis=(2, 4))


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "models/tiny-yolov3.onnx"
    convs = load_convs(path, set(WHICH))
    print("real tiny-yolov3 backbone: convs %s at %dx%d" % (list(WHICH), RES, RES))

    rng = np.random.default_rng(SEED)
    res = RES
    xmem = np.zeros((1, res, res, 4), np.int32)
    xmem[0, :, :, :3] = np.clip(
        np.round(rng.integers(0, 256, size=(res, res, 3)) / 255.0 * 127.0), -128, 127)
    img_mem = (xmem.reshape(-1) & 0xFF).astype(np.uint8)

    blob = bytearray()
    blob += img_mem.tobytes()                    # stage 0 input, at BUF_BASE+0
    table = []
    golds = []
    cur, cur_cin = xmem, 4
    for li, (idx, w, b, act) in enumerate(convs):
        cout, cin, kh, kw = w.shape
        # Only the stem differs: its 3 channels are zero-padded up to 4.
        assert cin == cur_cin or (li == 0 and cin < cur_cin), \
            "chain mismatch at conv %d: %d vs %d" % (idx, cin, cur_cin)
        wp = np.zeros((cout, cur_cin, kh, kw), np.float32)
        wp[:, :cin] = w
        wq, _ = P.quant(wp)
        bq = np.round(b).astype(np.int32)
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
            np.uint32((mult2 & 0xFFFF) | ((SHIFT & 0x1F) << 16)).tobytes(), np.uint8)

        wt_off = len(blob); blob += np.ascontiguousarray(wt).tobytes()
        bi_off = len(blob); blob += np.ascontiguousarray(bias).tobytes()
        cf_off = len(blob); blob += np.ascontiguousarray(cfg).tobytes()
        gold_off = len(blob); blob += np.ascontiguousarray(P.to_mem(q)).tobytes()

        print("  conv#%d %d->%d %dx%d wpad=%d nmt=%d rows=%d mult=%d a*mult=%d"
              "  out=%d gold=%d" % (idx, cin, cout, res, res, wpad, nmt,
                                   (cur_cin // 4) * kh * kw * (cout // 4),
                                   mult, mult2, int(np.prod(q.shape)), int(q.size)))
        table.append(dict(kind=0, h=res, w=res, cin=cur_cin, cout=cout, k=kh,
                          pad=1, out=OUT_OFF[li], a=0,
                          wt=wt_off, bias=bi_off, cfg=cf_off,
                          gold=gold_off, glen=int(q.size)))
        golds.append(q.size)

        if li < len(convs) - 1:
            pooled = pool_mem(P.to_mem(q), res, res, cout)
            blob += np.ascontiguousarray(
                (pooled.reshape(-1) & 0xFF).astype(np.uint8)).tobytes()
            nxt = res // 2
            table.append(dict(kind=1, h=res, w=res, cin=cout, cout=cout, k=2,
                              pad=0, out=OUT_OFF[li + 1], a=0, wt=0, bias=0,
                              cfg=0, gold=len(blob) - pooled.size,
                              glen=int(pooled.size)))
            cur = pooled
            res = nxt
            cur_cin = cout
        else:
            cur = None

    with open("models/ym_weights.bin", "wb") as f:
        f.write(bytes(blob))
    print("  blob: %d bytes (weights + goldens + input)" % len(blob))

    with open("integration/bsp/mt_yolomodel_weights.h", "w") as f:
        f.write("/* Auto-generated by integration/tools/pack_model.py."
                "  DO NOT EDIT. */\n")
        f.write("#ifndef MT_YOLOMODEL_WEIGHTS_H\n#define MT_YOLOMODEL_WEIGHTS_H\n\n")
        f.write("#define YM_BASE      0x%Xu\n" % BLOB_BASE)
        f.write("#define YM_PAD_OFF   0x%Xu\n" % PAD_OFF)
        f.write("#define YM_IMG_OFF   0u\n")
        f.write("#define YM_LAYERS    %d\n\n" % len(table))
        f.write("typedef struct {\n"
                "    unsigned char kind;   /* 0 conv, 1 pool2x2/2 */\n"
                "    unsigned short h, w;  /* output extent       */\n"
                "    unsigned short cin, cout;\n"
                "    unsigned char k, pad;\n"
                "    unsigned int out, wt, bias, cfg;   /* blob/buffer offsets */\n"
                "    unsigned int gold, glen;\n"
                "} ym_layer_t;\n\n")
        f.write("static const ym_layer_t ym_layers[YM_LAYERS] = {\n")
        for t in table:
            f.write("    {%d, %d, %d, %d, %d, %d, %d, 0x%Xu, 0x%Xu, 0x%Xu, 0x%Xu,"
                    " 0x%Xu, %d},\n"
                    % (t["kind"], t["h"], t["w"], t["cin"], t["cout"], t["k"],
                       t["pad"], t["out"], t["wt"], t["bias"], t["cfg"],
                       t["gold"], t["glen"]))
        f.write("};\n\n#endif\n")
    print("  wrote integration/bsp/mt_yolomodel_weights.h (%d layers)" % len(table))


if __name__ == "__main__":
    main()
