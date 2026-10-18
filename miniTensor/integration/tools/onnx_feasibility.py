#!/usr/bin/env python3
"""Check a real YOLO ONNX graph against what miniTensor can actually execute.

Walks the model in topological order, folds BatchNormalization into the
preceding convolution, propagates NCHW shapes, and reports per layer the MACs,
the packed weight volume and -- the point of the exercise -- whether the layer
is expressible on the accelerator at all.

The constraint list comes from the hardware, not from guesswork:
  c_in/c_out multiples of 4     MT_GEMM works on 4x4x4 INT8 tiles (zero-pad)
  W multiple of 4               net_conv addresses activations in 4-pixel tiles
                                (ntiles = W/4), so a 6-wide output cannot be
                                tiled at all -- real YOLO widths (414, 207, 205,
                                22, 11, 6) mostly violate this.  H is free: the
                                row loop is per-row.
  kernel 1 or 3                 net_pad's tap table
  ReLU and LeakyReLU supported  the epilogue has a ReLU bit, and for 0<a<1
                                leaky(x) = max(x, a*x) is two epilogues over
                                the same C tile (signed 16-bit multiplier) plus
                                the VPU's signed MAX8 -- verified bit-exactly on
                                a real trained stem in mt_yolo
  Sigmoid / SiLU / other LUTs   genuinely unsupported; needs an activation LUT
  pooling 2x2 stride 2          net_pool2 (stride 1 needs scheduler work)
  Concat / Resize               expressible (adjacent group blocks / row copies)
                                but the scheduler does not have them yet
  weight rows per tile <= 144   UB_WT capacity; net_conv reloads per group

Usage: .venv/bin/python integration/tools/onnx_feasibility.py <model.onnx> [H]
"""
import sys
from collections import Counter, defaultdict

import numpy as np
import onnx

ACTS = ("Relu", "LeakyRelu", "Sigmoid", "Clip", "HardSigmoid", "Tanh")
POOLS = ("MaxPool", "AveragePool", "GlobalAveragePool")


def dims_of(vi):
    return [d.dim_value for d in vi.type.tensor_type.shape.dim]


def attr(node, name, default=None):
    for a in node.attribute:
        if a.name == name:
            if a.type == onnx.AttributeProto.INTS:
                return list(a.ints)
            if a.type == onnx.AttributeProto.INT:
                return a.i
            if a.type == onnx.AttributeProto.FLOAT:
                return a.f
            if a.type == onnx.AttributeProto.STRING:
                return a.s.decode()
    return default


def main():
    path = sys.argv[1]
    res = int(sys.argv[2]) if len(sys.argv) > 2 else 416
    g = onnx.load(path).graph
    init = {i.name: onnx.numpy_helper.to_array(i) for i in g.initializer}

    consumer = defaultdict(list)
    for node in g.node:
        for t in node.input:
            consumer[t].append(node)

    shape = {n: tuple(a.shape) for n, a in init.items()}
    for vi in list(g.input) + list(g.value_info) + list(g.output):
        d = dims_of(vi)
        if len(d) == 4 and all(x > 0 for x in d):
            shape[vi.name] = tuple(d)
    for vi in g.input:
        d = dims_of(vi)
        if len(d) == 4 and not all(x > 0 for x in d):
            shape[vi.name] = (1, d[1] if d[1] > 0 else 3, res, res)

    rows = []
    notes = Counter()
    total_macs = 0
    handled_bn = set()

    def first_consumer(t, op_type):
        for c in consumer.get(t, ()):
            if c.op_type == op_type:
                return c
        return None

    for node in g.node:
        op = node.op_type
        x = shape.get(node.input[0]) if node.input else None

        if op == "Conv":
            w = init.get(node.input[1])
            if w is None or x is None:
                continue
            cout, cin, kh, kw = w.shape
            b = init[node.input[2]] if len(node.input) > 2 and node.input[2] in init \
                else None
            st = attr(node, "strides", [1, 1])
            pads = attr(node, "pads", [0, 0, 0, 0])
            H = (x[2] + pads[0] + pads[2] - kh) // st[0] + 1
            W = (x[3] + pads[1] + pads[3] - kw) // st[1] + 1

            tail = node.output[0]
            bn_node = first_consumer(tail, "BatchNormalization")
            if bn_node is not None and bn_node.input[0] == tail:
                sc, bb = init[bn_node.input[1]], init[bn_node.input[2]]
                mu, va = init[bn_node.input[3]], init[bn_node.input[4]]
                eps = attr(bn_node, "epsilon", 1e-5)
                k = sc / np.sqrt(va + eps)
                w = (w * k.reshape(-1, 1, 1, 1)).astype(np.float32)
                b = (bb - mu * k) if b is None else (b * k + (bb - mu * k))
                b = b.astype(np.float32)
                tail = bn_node.output[0]
                handled_bn.add(bn_node.output[0])

            act = "none"
            an = first_consumer(tail, None) if False else None
            for c in consumer.get(tail, ()):
                if c.op_type in ACTS:
                    an = c
                    break
            if an is not None and an.input[0] == tail:
                act = an.op_type
                tail = an.output[0]

            shape[tail] = (1, cout, H, W)
            if bn_node is not None:
                shape[bn_node.output[0]] = (1, cout, H, W)

            macs = cout * cin * kh * kw * H * W
            total_macs += macs
            rows.append(dict(op="Conv", cin=cin, cout=cout, k=kh, s=st[0], H=H,
                             W=W, act=act, macs=macs, wbytes=int(w.size),
                             rows=(cin // 4) * kh * kw * (cout // 4),
                             bn=bn_node is not None))

        elif op in POOLS:
            if x is None:
                continue
            ks = attr(node, "kernel_shape", [1, 1])
            st = attr(node, "strides", ks)
            H = max(1, (x[2] - ks[0]) // st[0] + 1)
            W = max(1, (x[3] - ks[1]) // st[1] + 1)
            shape[node.output[0]] = (1, x[1], H, W)
            rows.append(dict(op=op, cin=x[1], cout=x[1], k=ks[0], s=st[0], H=H,
                             W=W, act="none", macs=0, wbytes=0, rows=0, bn=False))

        elif op == "Concat":
            ins = [shape.get(i) for i in node.input if shape.get(i)]
            if ins:
                c = sum(i[1] for i in ins)
                shape[node.output[0]] = (1, c, ins[0][2], ins[0][3])
            notes["Concat"] += 1

        elif op in ("Resize", "Upsample"):
            if x:
                sc = attr(node, "scales")
                f = int(sc[-1]) if sc else 2
                shape[node.output[0]] = (1, x[1], x[2] * f, x[3] * f)
                notes["Resize/Upsample"] += 1

        elif op in ("Add", "Mul", "Sub", "Div"):
            if x:
                shape[node.output[0]] = x
            notes[op + " (eltwise)"] += 1

        elif op == "BatchNormalization":
            if node.output[0] not in shape and x:
                shape[node.output[0]] = x
        elif op in ACTS:
            if node.output[0] not in shape and x:
                shape[node.output[0]] = x
        else:
            for o in node.output:
                if o not in shape and x:
                    shape[o] = x

    print("=" * 92)
    print("miniTensor feasibility: %s  (assumed input %dx%d)"
          % (path.split("/")[-1], res, res))
    print("=" * 92)
    print("%3s %-10s %5s %5s %2s %2s %5s %5s %12s %9s %7s %-11s %s"
          % ("#", "op", "cin", "cout", "k", "s", "H", "W", "MACs", "wbytes",
             "wtrows", "act", "verdict"))
    viol = Counter()
    convs = [r for r in rows if r["op"] == "Conv"]
    for i, L in enumerate(rows):
        bad = []
        if L["op"] == "Conv":
            if L["cin"] % 4 or L["cout"] % 4:
                bad.append("pad channels to /4")
            if L["k"] not in (1, 3):
                bad.append("kernel%d" % L["k"])
            if L["s"] != 1:
                bad.append("stride%d" % L["s"])
            if L["act"] == "LeakyRelu":
                bad.append("leaky=2ep+MAX8")   # supported, at extra cost
            elif L["act"] not in ("Relu", "none"):
                bad.append(L["act"] + " UNSUPPORTED")
            if L["W"] % 4:
                bad.append("W%%4=%d" % L["W"])
            if L["rows"] > 144 and not bad:
                bad.append("needs tiling")
        elif L["op"] == "MaxPool":
            if L["k"] != 2 or L["s"] != 2:
                bad.append("pool%d/%d" % (L["k"], L["s"]))
        for b in bad:
            viol[b.split("(")[0]] += 1
        print("%3d %-10s %5d %5d %2d %2d %5d %5d %12d %9d %7d %-11s %s"
              % (i, L["op"], L["cin"], L["cout"], L["k"], L["s"], L["H"], L["W"],
                 L["macs"], L["wbytes"], L["rows"], L["act"],
                 ",".join(bad) if bad else "ok"))

    print()
    print("convolutions      : %d" % len(convs))
    print("total conv MACs   : %s (%.3f GMAC)" % (f"{sum(L['macs'] for L in convs):,}",
                                                  sum(L['macs'] for L in convs) / 1e9))
    print("conv weight bytes : %s" % f"{sum(L['wbytes'] for L in convs):,}")
    print("activation peak   : %s bytes (widest layer, INT8 [g][h][w][4])"
          % f"{max((L['H'] * L['W'] * L['cout'] for L in convs), default=0):,}")
    print("non-conv ops      : %s" % notes.most_common())
    print()
    hard = [L for L in convs if L["act"] not in ("Relu", "none", "LeakyRelu")]
    print("VERDICT")
    print("  convolutions needing an activation LUT (hard blocker): %d of %d"
          % (len(hard), len(convs)))
    n_geom = sum(1 for L in convs if L["W"] % 4)
    print("  convolutions whose W is not a multiple of 4                : %d of %d"
          % (n_geom, len(convs)))
    print("  convolutions needing only toolchain/scheduler work         : %d of %d"
          % (sum(1 for L in convs if (L["cin"] % 4 or L["cout"] % 4
                                      or L["k"] not in (1, 3) or L["s"] != 1
                                      or L["act"] == "LeakyRelu"
                                      or L["W"] % 4)), len(convs)))
    print("  reasons: %s" % viol.most_common())
    gmac = sum(L['macs'] for L in convs) / 1e9
    gemms = sum(L['macs'] for L in convs) / 64.0
    print()
    print("COST, two ways -- they differ by 4x, so be careful which one you quote:")
    print("  (a) GEMM-bound floor: 37 cycles per 64-MAC GEMM, measured with mt_perf")
    print("      %.3f GMAC -> %.2fG cycles -> %.2f s @300 MHz"
          % (gmac, gemms * 37.0 / 1e9, gemms * 37.0 / 3e8))
    print("  (b) END-TO-END, which is what a real network actually achieves: a")
    print("      convolution also has to load an A row per tap, run an epilogue per")
    print("      tile and store per row.  Measured 0.42 MAC/cycle on mt_net")
    print("      (745472 MACs / 1755461 cycles).")
    print("      %.3f GMAC -> %.2fG cycles -> %.2f s @300 MHz"
          % (gmac, gmac * 1e9 / 0.42 / 1e9, gmac * 1e9 / 0.42 / 3e8))
    print("  Verilator here runs about 3e5 cycles/s, so (b) is about %.1f hours of"
          " simulation." % (gmac * 1e9 / 0.42 / 3e5 / 3600))
    print("  Reducing the input resolution scales MACs quadratically: at 128x128 this")
    print("  model is %.2f GMAC, about %.0f minutes of simulation."
          % (gmac * (128.0 / res) ** 2, gmac * (128.0 / res) ** 2 * 1e9 / 0.42 / 3e5 / 60))


if __name__ == "__main__":
    main()
