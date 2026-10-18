#!/usr/bin/env python3
"""Pack the *complete* tiny-yolov3 graph for deployment on miniTensor.

Earlier fixtures ran slices of the backbone; this one walks the whole graph --
all 13 convolutions, all six max pools, the FPN upsample and the channel
concat -- and emits, for every stage, the packed INT8 weights and the integer
golden the accelerator must reproduce bit for bit.

    x -> conv3x3 3->16    -> pool2/2 -> conv3x3 16->32   -> pool2/2
      -> conv3x3 32->64   -> pool2/2 -> conv3x3 64->128  -> pool2/2
      -> conv3x3 128->256 -> pool2/2 -> conv3x3 256->512 -> pool2/1(SAME)
      -> conv3x3 512->1024 -> conv1x1 1024->256
           |-> conv1x1 256->128 -> upsample x2 --\
           |-> conv3x3 256->512 -> head 1x1 512->255
           +-> (concat with the 128->256 layer) -> conv3x3 384->256 -> head 1x1 256->255

Everything is addressed relative to ONE base in the uncached 12 MiB window.
The C side gets that base from the linker (__model_start), so the blob can be
placed anywhere without regenerating this header.

Outputs:
    models/ym_weights.bin
    integration/bsp/mt_yolomodel_weights.h
"""
import sys
import numpy as np
import onnx

import pack_weights as P

RES = 64
ALPHA = 0.1
SHIFT = 14
SEED = 0x13579BDF
WEIGHTS_REGION_BYTES = 12 * 1024 * 1024


def load_convs(path):
    """name -> (w, b, act) for every Conv, with BatchNormalization folded."""
    g = onnx.load(path).graph
    init = {i.name: onnx.numpy_helper.to_array(i) for i in g.initializer}
    out = {}
    for node in g.node:
        if node.op_type != "Conv":
            continue
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
        out[node.name] = (w, b, act)
    return out


# --------------------------------------------------------- integer primitives
def hwc(mem, h, sw, c):
    """[g][h][sw][4] bytes -> signed (h, sw, c)."""
    return P.from_mem(mem, h, sw, c)


def conv_tot(S, W, wpad, wq, bq, k, pad, cout):
    """Raw accumulators (acc + bias), before requantisation."""
    h, sw, cin = S["h"], S["stride"], S["c"]
    a = hwc(S["mem"], h, sw, cin)
    xp = np.zeros((h, wpad, cin), np.int64)
    xp[:, :W, :] = a[:, :W, :].astype(np.int64)
    xpad = np.zeros((h + 2 * pad, wpad + 2 * pad, cin), np.int64)
    xpad[pad:pad + h, pad:pad + wpad, :] = xp
    acc = np.zeros((h, wpad, cout), np.int64)
    for ky in range(k):
        for kx in range(k):
            acc += np.einsum('hwc,oc->hwo',
                             xpad[ky:ky + h, kx:kx + wpad, :],
                             wq[:, :, ky, kx].astype(np.int64))
    return acc + bq[None, None, :].astype(np.int64)


def conv_requant(tot, mult, shift, mult2, leaky):
    """Epilogue: (tot * mult) >> shift, plus the a*x pass behind MAX8 for
    LeakyReLU, then saturate to INT8."""
    v1 = (tot * np.int64(mult)) >> np.int64(shift)
    if leaky:
        v = np.maximum(v1, (tot * np.int64(mult2)) >> np.int64(shift))
    else:
        v = v1
    return P.to_mem(np.clip(v, -128, 127).astype(np.int32))


def pool2_int(S):
    assert S["w"] == S["stride"], "stride-2 pool only used on un-strided maps"
    return P.pool_mem(S["mem"], S["h"], S["w"], S["c"])


def pool_same_int(S, k, stride):
    h, w, sw, c = S["h"], S["w"], S["stride"], S["c"]
    ng = c // 4
    a = P.signed8(S["mem"]).reshape(ng, h, sw, 4)
    oh, ow = (h + stride - 1) // stride, (w + stride - 1) // stride
    out = np.full((ng, oh, ow, 4), -128, np.int32)
    for oy in range(oh):
        for ox in range(ow):
            best = np.full((ng, 4), -128, np.int32)
            for ky in range(k):
                iy = oy * stride + ky
                if iy >= h:
                    continue
                for kx in range(k):
                    ix = ox * stride + kx
                    if ix >= w:
                        continue
                    best = np.maximum(best, a[:, iy, ix, :])
            out[:, oy, ox, :] = best
    return (out.reshape(-1) & 0xFF).astype(np.uint8)


def upsample2_int(S):
    h, w, sw, c = S["h"], S["w"], S["stride"], S["c"]
    ng = c // 4
    a = P.signed8(S["mem"]).reshape(ng, h, sw, 4)[:, :, :w, :]
    out = np.repeat(np.repeat(a, 2, axis=1), 2, axis=2)
    return (out.reshape(-1) & 0xFF).astype(np.uint8)


def conv_float(a, w, b, pad):
    h, ww, cin = a.shape
    k = w.shape[2]
    cout = w.shape[0]
    xp = np.pad(a, ((pad, pad), (pad, pad), (0, 0)))
    out = np.zeros((h, ww, cout), np.float64)
    for ky in range(k):
        for kx in range(k):
            out += np.einsum('hwc,oc->hwo', xp[ky:ky + h, kx:kx + ww, :],
                             w[:, :, ky, kx])
    return out + b


def pool2_float(a):
    h, w, c = a.shape
    return a.reshape(h // 2, 2, w // 2, 2, c).max(axis=(1, 3))


def pool_same_float(a, k, stride):
    h, w, c = a.shape
    oh, ow = (h + stride - 1) // stride, (w + stride - 1) // stride
    out = np.full((oh, ow, c), -np.inf)
    for oy in range(oh):
        for ox in range(ow):
            best = np.full(c, -np.inf)
            for ky in range(k):
                iy = oy * stride + ky
                if iy >= h:
                    continue
                for kx in range(k):
                    ix = ox * stride + kx
                    if ix >= w:
                        continue
                    best = np.maximum(best, a[iy, ix])
            out[oy, ox] = best
    return out


def calibrate(convs, img4):
    """Float forward pass: max|activation| of every stage, for quantisation."""
    fb = {-1: img4}
    maxabs = {-1: 1.0}
    for oi, (kind, name) in enumerate(SEQ):
        if kind == "conv":
            w, b, act = convs[name]
            S = fb[SRC[oi]]
            cout, cin_w, kh, kw = w.shape
            cin = S.shape[2]
            wp = np.zeros((cout, cin, kh, kw), np.float32)
            wp[:, :cin_w] = w
            f = conv_float(S, wp, b, kh // 2)
            if act == "LeakyRelu":
                f = np.where(f >= 0, f, 0.1 * f)
        elif kind == "pool":
            f = pool2_float(fb[SRC[oi]])
        elif kind == "poolsame":
            f = pool_same_float(fb[SRC[oi]], 2, 1)
        elif kind == "up":
            f = np.repeat(np.repeat(fb[SRC[oi]], 2, axis=0), 2, axis=1)
        else:
            ai, bi = CAT[oi]
            f = np.concatenate([fb[ai], fb[bi]], axis=2)
        fb[oi] = f
        maxabs[oi] = float(np.max(np.abs(f)))
    return maxabs


SEQ = [
    ("conv", "conv2d_1"),      # 0  3->16     64x64
    ("pool", None),            # 1            32x32
    ("conv", "conv2d_2"),      # 2  16->32
    ("pool", None),            # 3            16x16
    ("conv", "conv2d_3"),      # 4  32->64
    ("pool", None),            # 5            8x8
    ("conv", "conv2d_4"),      # 6  64->128
    ("pool", None),            # 7            4x4
    ("conv", "conv2d_5"),      # 8  128->256
    ("pool", None),            # 9            2x2
    ("conv", "conv2d_6"),      # 10 256->512
    ("poolsame", None),        # 11 2x2/1 SAME
    ("conv", "conv2d_7"),      # 12 512->1024
    ("conv", "conv2d_8"),      # 13 1024->256
    ("conv", "conv2d_11"),     # 14 256->128   (branch A)
    ("up", None),              # 15 x2        4x4
    ("cat", None),             # 16 128+256=384
    ("conv", "conv2d_9"),      # 17 256->512   (branch B)
    ("conv", "conv2d_12"),     # 18 384->256
    ("conv", "conv2d_10"),     # 19 head 512->255
    ("conv", "conv2d_13"),     # 20 head 256->255
]
SRC = {0: -1, 1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 7, 9: 8, 10: 9,
       11: 10, 12: 11, 13: 12, 14: 13, 15: 14, 17: 13, 18: 16, 19: 17, 20: 18}
CAT = {16: (15, 8)}


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "models/tiny-yolov3.onnx"
    convs = load_convs(path)

    rng = np.random.default_rng(SEED)
    yy, xx = np.mgrid[0:RES, 0:RES]
    img = np.zeros((RES, RES, 3), np.float32)
    img[(yy - 22.0) ** 2 + (xx - 42.0) ** 2 < 12.0 ** 2] = 1.0
    img[14:20, 8:56] = 0.55
    xmem = np.zeros((RES, RES, 4), np.int32)
    xmem[:, :, :3] = np.clip(np.round(img * 127.0), -128, 127)
    img_mem = (xmem.reshape(-1) & 0xFF).astype(np.uint8)

    # Calibrate the per-layer activation scales on the float model first.  The
    # earlier fixtures skipped this and used bq = round(b); the network then ran
    # bit-exactly but was not numerically faithful, so its detections were
    # meaningless.  With per-layer s_x the requant keeps the float model's
    # meaning and the heads can be decoded.
    maxabs = calibrate(convs, xmem.astype(np.float64) / 127.0)

    bufs = {-1: dict(mem=img_mem, h=RES, w=RES, c=4, stride=RES)}
    golds, meta, packed = {}, {}, {}

    for oi, (kind, name) in enumerate(SEQ):
        if kind == "conv":
            w, b, act = convs[name]
            cout, cin_w, kh, kw = w.shape
            S = bufs[SRC[oi]]
            # The engine works in channel groups of four, so the stem's three
            # input channels are zero-padded to four, exactly as before.
            cin = S["c"]
            assert cin_w == cin or (oi == 0 and cin_w < cin), \
                "channel mismatch at %s: %d vs %d" % (name, cin_w, cin)
            W, wpad = S["w"], ((S["w"] + 3) // 4) * 4
            cout_p = ((cout + 3) // 4) * 4
            wp = np.zeros((cout_p, cin, kh, kw), np.float32)
            wp[:cout, :cin_w] = w
            b_p = np.zeros(cout_p, np.float32)
            b_p[:cout] = b
            wq, s_w = P.quant(wp)
            # Bias and requant factor in accumulator units, from the calibrated
            # input scale s_x_in = max|activation_in| / 127 and the weight scale.
            s_x_in = max(1e-9, maxabs[SRC[oi]]) / 127.0
            bq = np.round(b_p / (s_x_in * s_w)).astype(np.int32)
            pad = kh // 2
            nmt = P.choose_nmt(dict(h=S["h"], w=wpad, c_in=cin,
                                    c_out=cout_p, k=kh))
            s_out = max(1e-9, maxabs[oi]) / 127.0
            ratio = s_x_in * s_w / s_out
            shift = 0
            while shift < 31 and ratio * (1 << (shift + 1)) <= 32767:
                shift += 1
            mult = max(1, min(32767, int(round(ratio * (1 << shift)))))
            leaky = 1 if act == "LeakyRelu" else 0
            mult2 = max(1, min(32767, int(round(mult * ALPHA)))) if leaky else 1
            tot = conv_tot(S, W, wpad, wq, bq, kh, pad, cout_p)
            mem = conv_requant(tot, mult, shift, mult2, leaky)
            wt, bias, cfg16 = P.to_rows(wq, dict(h=S["h"], w=wpad, c_in=cin,
                                                 c_out=cout_p, k=kh),
                                        mult, shift, bq, 0, 0, nmt)
            cfg = np.zeros(32, np.uint8)
            cfg[0:16] = cfg16
            if leaky:
                cfg[16:20] = np.frombuffer(
                    np.uint32((mult2 & 0xFFFF) | ((shift & 0x1F) << 16)).tobytes(),
                    np.uint8)
            bufs[oi] = dict(mem=mem, h=S["h"], w=W, c=cout_p, stride=wpad)
            golds[oi] = mem
            packed[oi] = dict(wt=wt, bias=bias, cfg=cfg, nmt=nmt)
            meta[oi] = dict(kind=0, h=S["h"], w=W, cin=cin, cout=cout_p, k=kh,
                            pad=pad, leaky=leaky, src_w=S["stride"], wpad=wpad,
                            hint="%s %d->%d k%d" % (name, cin, cout_p, kh))
            print("  %-16s %4d->%-4d k%d  %2dx%-2d wpad=%d nmt=%d mult=%-5d "
                  "leaky=%d" % (name, cin, cout_p, kh, S["h"], W, wpad, nmt,
                                mult, leaky))
        elif kind in ("pool", "poolsame"):
            S = bufs[SRC[oi]]
            if kind == "pool":
                mem = pool2_int(S)
                oh, ow = S["h"] // 2, S["w"] // 2
            else:
                mem = pool_same_int(S, 2, 1)
                oh, ow = S["h"], S["w"]
            bufs[oi] = dict(mem=mem, h=oh, w=ow, c=S["c"], stride=ow)
            golds[oi] = mem
            meta[oi] = dict(kind=1 if kind == "pool" else 2, h=S["h"], w=S["w"],
                            cin=S["c"], cout=S["c"], k=2, pad=2 if kind == "pool" else 1,
                            leaky=0, src_w=S["stride"], wpad=ow,
                            hint="%s %dx%d" % (kind, S["h"], S["w"]))
            print("  %-16s %2dx%-2d -> %2dx%-2d  (%d ch)"
                  % (kind, S["h"], S["w"], oh, ow, S["c"]))
        elif kind == "up":
            S = bufs[SRC[oi]]
            mem = upsample2_int(S)
            bufs[oi] = dict(mem=mem, h=2 * S["h"], w=2 * S["w"], c=S["c"],
                            stride=2 * S["w"])
            golds[oi] = mem
            meta[oi] = dict(kind=3, h=S["h"], w=S["w"], cin=S["c"], cout=S["c"],
                            k=0, pad=0, leaky=0, src_w=S["stride"],
                            wpad=2 * S["w"], hint="upsample x2")
            print("  %-16s %2dx%-2d -> %2dx%-2d" % ("upsample", S["h"], S["w"],
                                                     2 * S["h"], 2 * S["w"]))
        else:
            ai, bi = CAT[oi]
            A, B = bufs[ai], bufs[bi]
            assert (A["h"], A["w"], A["stride"]) == (B["h"], B["w"], B["stride"])
            mem = np.concatenate([A["mem"], B["mem"]]).astype(np.uint8)
            bufs[oi] = dict(mem=mem, h=A["h"], w=A["w"], c=A["c"] + B["c"],
                            stride=A["stride"])
            golds[oi] = mem
            meta[oi] = dict(kind=4, h=A["h"], w=A["w"], cin=A["c"], cout=B["c"],
                            k=0, pad=0, leaky=0, src_w=A["stride"],
                            wpad=A["stride"], hint="concat %d+%d" % (A["c"], B["c"]))
            print("  %-16s %d + %d -> %d ch @ %dx%d"
                  % ("concat", A["c"], B["c"], A["c"] + B["c"], A["h"], A["w"]))

    # ---- scratch (not part of the file): activations then padding ----------
    act_off, off = {}, 0
    for oi in range(len(SEQ)):
        m = meta[oi]
        if m["kind"] == 0:
            size = (m["cout"] // 4) * m["h"] * m["wpad"] * 4
        elif m["kind"] == 1:
            size = (m["cout"] // 4) * (m["h"] // 2) * (m["w"] // 2) * 4
        elif m["kind"] == 2:
            size = (m["cout"] // 4) * m["h"] * m["w"] * 4
        elif m["kind"] == 3:
            size = (m["cout"] // 4) * (2 * m["h"]) * (2 * m["w"]) * 4
        else:
            size = ((m["cin"] + m["cout"]) // 4) * m["h"] * m["w"] * 4
        act_off[oi] = off
        off = (off + size + 15) & ~15
    act_bytes = off
    pad_rel = (act_bytes + 15) & ~15
    pad_need = max(3 * (m["cin"] // 4) * (m["h"] + 2) * m["wpad"] * 4
                   for oi, m in meta.items() if m["kind"] == 0 and m["k"] == 3)

    # ---- file layout: input | weights/biases/cfgs | goldens -----------------
    blob = bytearray(img_mem.tobytes())
    for oi in range(len(SEQ)):
        if oi not in packed:
            continue
        pk = packed[oi]
        pk["wt_off"] = len(blob);   blob += pk["wt"].tobytes()
        pk["bias_off"] = len(blob); blob += pk["bias"].tobytes()
        pk["cfg_off"] = len(blob);  blob += pk["cfg"].tobytes()
    for oi in range(len(SEQ)):
        meta[oi]["gold"] = len(blob)
        meta[oi]["glen"] = len(golds[oi])
        blob += golds[oi].tobytes()

    scratch = (len(blob) + 15) & ~15
    for oi in range(len(SEQ)):
        meta[oi]["out"] = scratch + act_off[oi]
        if oi in packed:
            meta[oi]["wt"] = packed[oi]["wt_off"]
            meta[oi]["bias"] = packed[oi]["bias_off"]
            meta[oi]["cfg"] = packed[oi]["cfg_off"]
    pad_abs = scratch + pad_rel
    total = scratch + pad_rel + pad_need
    print("blob file %d B (%.2f MiB); scratch %d B; pad %d B at +0x%X; "
          "total %.2f MiB / 12 MiB"
          % (len(blob), len(blob) / 1048576.0, act_bytes, pad_need, pad_abs,
             total / 1048576.0))
    print("goldens end at +0x%X (small tests' scratch starts at 0x80D80000 = "
          "+0x%X from 0x80406400)" % (scratch, 0x80D80000 - 0x80406400))
    assert total <= WEIGHTS_REGION_BYTES, "blob does not fit the 12 MiB window"

    with open("models/ym_weights.bin", "wb") as f:
        f.write(bytes(blob))

    def src_of(oi):
        if oi == 0:
            return 0, 0
        if oi in CAT:
            a, b = CAT[oi]
            return meta[a]["out"], meta[b]["out"]
        return meta[SRC[oi]]["out"], 0

    with open("integration/bsp/mt_yolomodel_weights.h", "w") as f:
        f.write("/* Auto-generated by integration/tools/pack_full.py."
                "  DO NOT EDIT. */\n")
        f.write("#ifndef MT_YOLOMODEL_WEIGHTS_H\n#define MT_YOLOMODEL_WEIGHTS_H\n\n")
        f.write("#define YM_LAYERS   %d\n" % len(SEQ))
        f.write("#define YM_PAD_OFF  0x%Xu\n" % pad_rel)
        f.write("#define YM_PAD_SIZE 0x%Xu\n" % pad_need)
        f.write("#define YM_SCRATCH  0x%Xu\n" % scratch)
        f.write("#define YM_IMG_OFF  0u\n\n")
        f.write("typedef struct {\n"
                "    unsigned char  kind;   /* 0 conv 1 pool2/2 2 pool2/1SAME "
                "3 upsample2 4 concat */\n"
                "    unsigned char  k, pad, leaky;\n"
                "    unsigned short h, w, cin, cout;\n"
                "    unsigned short src_w, wpad;\n"
                "    unsigned int   src, src2, out, wt, bias, cfg;\n"
                "    unsigned int   gold, glen;\n"
                "} ym_layer_t;\n\n")
        f.write("static const ym_layer_t ym_layers[YM_LAYERS] = {\n")
        for oi in range(len(SEQ)):
            m = meta[oi]
            src, src2 = src_of(oi)
            f.write("    {%d, %d, %d, %d, %d, %d, %d, %d, %d, %d,"
                    " 0x%Xu, 0x%Xu, 0x%Xu, 0x%Xu, 0x%Xu, 0x%Xu, 0x%Xu, %d},"
                    "  /* %s */\n"
                    % (m["kind"], m["k"], m["pad"], m["leaky"], m["h"], m["w"],
                       m["cin"], m["cout"], m["src_w"], m["wpad"],
                       src, src2, m["out"], m.get("wt", 0), m.get("bias", 0),
                       m.get("cfg", 0), m["gold"], m["glen"], m["hint"]))
        f.write("};\n\n#endif\n")
    print("wrote models/ym_weights.bin and integration/bsp/mt_yolomodel_weights.h")


if __name__ == "__main__":
    main()
