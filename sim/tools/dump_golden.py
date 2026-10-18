import sys, numpy as np
sys.path.insert(0, 'miniTensor/integration/tools')
import pack_weights as pw

d = np.load('miniTensor/integration/tools/detector_float.npz')
w1, w2, w3 = d['w1'], d['w2'], d['w3']
wh, bh = d['wh'], d['bh']
xte, yte = d['xte'], d['yte']
conv_w = [w1, w2, w3]
head_w = wh.reshape(8, 16, 1, 1)
biases = [np.zeros(8), np.zeros(16), np.zeros(16), bh]
mx = [0.0, 0.0, 0.0, 0.0]
for i in range(xte.shape[0]):
    a = xte[i]
    for li in range(3):
        L = pw.LAYERS[li]
        a = pw.conv_float(a, conv_w[li], biases[li], L['pad'])
        if L['relu']:
            a = np.maximum(a, 0.0)
        mx[li] = max(mx[li], float(np.max(np.abs(a))))
        if li < 2:
            a = pw.pool2(a)
    o = pw.conv_float(a, head_w, bh, 0)
    mx[3] = max(mx[3], float(np.max(np.abs(o))))
s_in = [1.0/127.0] + [m/127.0 for m in mx]
packed = []
for li, L in enumerate(pw.LAYERS):
    w = [w1, w2, w3, head_w][li]
    b = biases[li]
    wq, s_w = pw.quant(w)
    s_x_in, s_x_out = s_in[li], s_in[li+1]
    ratio = s_x_in * s_w / s_x_out
    shift = 0
    while shift < pw.SHIFT_MAX and ratio * (1 << (shift+1)) <= pw.MULT_MAX:
        shift += 1
    mult = int(round(ratio * (1 << shift)))
    mult = max(1, min(pw.MULT_MAX, mult))
    bq = np.round(b / (s_x_in * s_w)).astype(np.int32)
    nmt = pw.choose_nmt(L)
    wt, bias, cfg = pw.to_rows(wq, L, mult, shift, bq, 0, L['relu'], nmt)
    packed.append(dict(wt=wt, bias=bias, cfg=cfg, bias_q=bq, nmt=nmt,
                       mult=mult, shift=shift, zp=0, relu=L['relu']))
imgs = np.zeros((xte.shape[0], pw.H*pw.W*pw.C_IN), dtype=np.uint8)
for i in range(xte.shape[0]):
    img = np.round(xte[i,:,:,0] / s_in[0]).astype(np.int32)
    img = np.clip(img, -128, 127).reshape(pw.H, pw.W, 1)
    flat = np.zeros((pw.H, pw.W, pw.C_IN), dtype=np.int32)
    flat[:,:,0] = img[:,:,0]
    imgs[i] = (flat.reshape(-1) & 0xFF).astype(np.uint8)
trace = []
pw.int_forward(imgs[0], packed, trace)
for name, mem in trace:
    print(name, bytes(mem[:256]).hex())
