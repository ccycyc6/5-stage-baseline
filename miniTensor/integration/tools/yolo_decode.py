#!/usr/bin/env python3
"""Decode the two YOLO heads the full model leaves in the blob.

The accelerator's job ends at the two 1x1 head convolutions (conv2d_10 and
conv2d_13).  This script reads THEIR golden bytes out of models/ym_weights.bin
(which the hardware reproduces bit for bit) and applies the standard YOLOv3
decode: sigmoid on xy/obj/classes, exp on wh, anchors, grid offset, then
per-class NMS.  It is the software half of the deployment -- what a host or a
second stage on the CPU would do with the accelerator's output.

It also re-runs the same decode on a NumPy float forward pass so the quantised
result can be compared.

    .venv/bin/python integration/tools/yolo_decode.py
"""
import re
import sys

import numpy as np

import pack_weights as P
import pack_full as PF

RES = 64
SEED = 0x13579BDF
# anchors extracted from the ONNX constants (TFNodes/.../Const:0, Const_2:0),
# in the order the graph applies them: the coarse 2x2 head uses the large ones.
ANCHORS = {
    "head1_coarse": np.array([[81.0, 82.0], [135.0, 169.0], [344.0, 319.0]]),
    "head2_fine": np.array([[23.0, 27.0], [37.0, 58.0], [81.0, 82.0]]),
}


def make_image():
    yy, xx = np.mgrid[0:RES, 0:RES]
    img = np.zeros((RES, RES, 3), np.float32)
    img[(yy - 22.0) ** 2 + (xx - 42.0) ** 2 < 12.0 ** 2] = 1.0
    img[14:20, 8:56] = 0.55
    xmem = np.zeros((RES, RES, 4), np.int32)
    xmem[:, :, :3] = np.clip(np.round(img * 127.0), -128, 127)
    return xmem


def parse_header(path):
    txt = open(path).read()
    body = txt.split("ym_layers[YM_LAYERS] = {", 1)[1].split("};", 1)[0]
    fields = ["kind", "k", "pad", "leaky", "h", "w", "cin", "cout", "src_w",
              "wpad", "src", "src2", "out", "wt", "bias", "cfg", "gold", "glen"]
    rows = []
    for line in body.splitlines():
        line = line.split("/*")[0].strip()
        if not line.startswith("{"):
            continue
        raw_vals = [v.strip().rstrip("uU") for v in line.strip("{},").split(",")]
        vals = [int(v, 0) for v in raw_vals]
        rows.append(dict(zip(fields, vals)))
    return rows


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def decode(raw, anchors, grid_h, grid_w):
    """raw: (h, w, 3, 85) already dequantised."""
    xy = sigmoid(raw[..., 0:2])
    wh = np.exp(np.clip(raw[..., 2:4], -20.0, 20.0))
    obj = sigmoid(raw[..., 4])
    cls = sigmoid(raw[..., 5:])
    score = obj[..., None] * cls
    best_cls = np.argmax(score, axis=-1)
    best_score = np.max(score, axis=-1)

    gy, gx = np.mgrid[0:grid_h, 0:grid_w]
    cx = (gx[..., None] + xy[..., 0]) / grid_w
    cy = (gy[..., None] + xy[..., 1]) / grid_h
    bw = wh[..., 0] * anchors[None, None, :, 0] / RES
    bh = wh[..., 1] * anchors[None, None, :, 1] / RES

    boxes = np.stack([cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2], -1)
    return boxes, best_score, best_cls


def nms(boxes, scores, cls, iou_thr=0.45, score_thr=0.05):
    keep = []
    order = np.argsort(-scores)
    for i in order:
        if scores[i] < score_thr:
            break
        suppress = False
        for j in keep:
            if cls[i] != cls[j]:
                continue
            x0 = max(boxes[i, 0], boxes[j, 0])
            y0 = max(boxes[i, 1], boxes[j, 1])
            x1 = min(boxes[i, 2], boxes[j, 2])
            y1 = min(boxes[i, 3], boxes[j, 3])
            inter = max(0.0, x1 - x0) * max(0.0, y1 - y0)
            ai = (boxes[i, 2] - boxes[i, 0]) * (boxes[i, 3] - boxes[i, 1])
            aj = (boxes[j, 2] - boxes[j, 0]) * (boxes[j, 3] - boxes[j, 1])
            if inter / max(1e-9, ai + aj - inter) > iou_thr:
                suppress = True
                break
        if not suppress:
            keep.append(i)
    return keep


def head_scale(cfg):
    """mult/shift from the packed 16-byte config row; raw = int8 * 2**shift/mult."""
    word = int.from_bytes(cfg[0:4], "little")
    mult = word & 0xFFFF
    shift = (word >> 16) & 0x1F
    return (1 << shift) / float(mult)


def main():
    rows = parse_header("integration/bsp/mt_yolomodel_weights.h")
    blob = open("models/ym_weights.bin", "rb").read()

    # Each int8 activation represents f/s_out with s_out = max|f|/127, so the
    # decode needs the calibrated float scale, not the accumulator requant
    # factor that is packed in the config row.
    convs = PF.load_convs("models/tiny-yolov3.onnx")
    maxabs = PF.calibrate(convs, make_image().astype(np.float64) / 127.0)
    head_oi = [i for i, (k, _) in enumerate(PF.SEQ) if k == "conv"][-2:]

    heads = [r for r in rows if r["kind"] == 0][-2:]
    names = ["head1_coarse (2x2, 512->255)", "head2_fine (4x4, 256->255)"]
    anchors = [ANCHORS["head1_coarse"], ANCHORS["head2_fine"]]

    all_boxes, all_scores, all_cls = [], [], []
    for r, name, anc, oi in zip(heads, names, anchors, head_oi):
        cout = r["cout"]
        mem = np.frombuffer(blob[r["gold"]:r["gold"] + r["glen"]], np.uint8)
        a = P.from_mem(mem, r["h"], r["wpad"], cout)[:, :r["w"], :255]
        s = maxabs[oi] / 127.0
        raw = a.astype(np.float64) * s
        grid_h, grid_w = r["h"], r["w"]
        raw = raw.reshape(grid_h, grid_w, 3, 85)
        boxes, score, cls = decode(raw, anc, grid_h, grid_w)
        print("%s: grid %dx%d, scale %.3f, raw range %.1f..%.1f, "
              "max obj*cls %.4f" % (name, grid_h, grid_w, s,
                                    raw.min(), raw.max(), score.max()))
        all_boxes.append(boxes.reshape(-1, 4))
        all_scores.append(score.reshape(-1))
        all_cls.append(cls.reshape(-1))

    boxes = np.concatenate(all_boxes)
    scores = np.concatenate(all_scores)
    cls = np.concatenate(all_cls)
    keep = nms(boxes, scores, cls)
    print("after NMS: %d detection(s)" % len(keep))
    for i in keep[:10]:
        print("  class %3d score %.3f box [%.3f %.3f %.3f %.3f] (normalised)"
              % (cls[i], scores[i], boxes[i, 0], boxes[i, 1],
                 boxes[i, 2], boxes[i, 3]))


if __name__ == "__main__":
    main()
