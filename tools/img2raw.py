#!/usr/bin/env python3
"""Convert a photo (PGM / PPM / BMP) into the ARES-P4 vision demo frame.

The board expects exactly 1024 bytes: 32x32, row major, 8-bit grey,
0 = background, 255 = foreground.

Usage
  python tools/img2raw.py photo.bmp out.raw
  python tools/img2raw.py photo.bmp out.raw --invert --threshold 120
  python tools/img2raw.py --demo circle demo_circle.raw [--noise 12]

The --demo mode renders the same synthetic shapes the firmware uses, so the
serial upload path can be checked without a camera or a real photo.
"""
import argparse
import struct
import sys

W = H = 32


# --------------------------------------------------------------------- readers
def read_pnm(path):
    with open(path, 'rb') as f:
        data = f.read()
    if data[:2] not in (b'P5', b'P6'):
        raise SystemExit('only binary PGM (P5) / PPM (P6) are supported')
    channels = 1 if data[:2] == b'P5' else 3
    pos = 2
    fields = []
    while len(fields) < 3:
        while pos < len(data) and data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b'#':
            while pos < len(data) and data[pos:pos + 1] != b'\n':
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(int(data[start:pos]))
    w, h, maxv = fields
    pos += 1  # single whitespace after maxval
    if maxv > 255:
        raise SystemExit('16-bit PNM is not supported, convert to 8-bit first')
    px = data[pos:pos + w * h * channels]
    if len(px) < w * h * channels:
        raise SystemExit('truncated PNM file')
    return w, h, channels, px


def read_bmp(path):
    with open(path, 'rb') as f:
        data = f.read()
    if data[:2] != b'BM':
        raise SystemExit('not a BMP file')
    off = struct.unpack_from('<I', data, 10)[0]
    dib = struct.unpack_from('<I', data, 14)[0]
    if dib < 40:
        raise SystemExit('unsupported BMP header')
    w, h = struct.unpack_from('<ii', data, 18)
    bpp = struct.unpack_from('<H', data, 28)[0]
    comp = struct.unpack_from('<I', data, 30)[0]
    if comp != 0:
        raise SystemExit('compressed BMP is not supported, save as 24-bit BMP')
    if bpp not in (24, 32):
        raise SystemExit('only 24/32-bit BMP is supported')
    topdown = h < 0
    h = abs(h)
    channels = 1
    row = ((w * bpp // 8) + 3) & ~3
    out = bytearray(w * h)
    for y in range(h):
        src_y = y if topdown else (h - 1 - y)
        base = off + src_y * row
        for x in range(w):
            p = base + x * (bpp // 8)
            b, g, r = data[p], data[p + 1], data[p + 2]
            out[y * w + x] = (77 * r + 150 * g + 29 * b) >> 8
    return w, h, channels, bytes(out)


def load_gray(path):
    ext = path.lower().rsplit('.', 1)[-1]
    if ext == 'bmp':
        return read_bmp(path)
    return read_pnm(path)


# ------------------------------------------------------------------ transforms
def resize_box(w, h, ch, px):
    """Box-average down/up to 32x32 grey."""
    out = bytearray(W * H)
    for y in range(H):
        y0 = (y * h) // H
        y1 = max(y0 + 1, ((y + 1) * h) // H)
        for x in range(W):
            x0 = (x * w) // W
            x1 = max(x0 + 1, ((x + 1) * w) // W)
            acc = 0
            cnt = 0
            for sy in range(y0, min(y1, h)):
                for sx in range(x0, min(x1, w)):
                    i = (sy * w + sx) * ch
                    acc += px[i]
                    cnt += 1
            out[y * W + x] = acc // cnt if cnt else 0
    return out


def auto_contrast(img):
    lo, hi = min(img), max(img)
    if hi - lo < 8:
        return img
    return bytearray(((v - lo) * 255) // (hi - lo) for v in img)


def threshold(img, thr):
    return bytearray(255 if v >= thr else 0 for v in img)


# ----------------------------------------------------------------- demo shapes
def render(cls, cx=16, cy=16, r=12, noise=0, seed=7):
    state = seed & 0xFFFFFFFF or 1

    def rnd(n):
        nonlocal state
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        return (state >> 16) % n

    img = bytearray(W * H)
    rin = (r * 55) // 100
    for y in range(H):
        for x in range(W):
            dx, dy = x - cx, y - cy
            if cls == 'circle':
                on = dx * dx + dy * dy <= r * r
            elif cls == 'square':
                on = -r <= dx <= r and -r <= dy <= r
            elif cls == 'triangle':
                hh = y - (cy - r)
                on = False
                if 0 <= hh <= 2 * r:
                    half = (hh * r) // (2 * r)
                    on = -half <= dx <= half
            elif cls == 'cross':
                on = ((-r // 3 <= dx <= r // 3 and -r <= dy <= r) or
                      (-r // 3 <= dy <= r // 3 and -r <= dx <= r))
            elif cls == 'ring':
                on = rin * rin <= dx * dx + dy * dy <= r * r
            else:
                raise SystemExit('unknown demo class ' + cls)
            img[y * W + x] = 255 if on else 0
    if noise:
        for i in range(len(img)):
            img[i] = max(0, min(255, img[i] + rnd(2 * noise + 1) - noise))
    return img


def preview(img):
    lines = []
    for y in range(0, H, 2):
        row = []
        for x in range(0, W, 2):
            v = img[y * W + x] + img[y * W + x + 1] + \
                img[(y + 1) * W + x] + img[(y + 1) * W + x + 1]
            row.append('#' if v > 400 else ('+' if v > 120 else '.'))
        lines.append(''.join(row))
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src', nargs='?', help='PGM/PPM/BMP photo')
    ap.add_argument('dst', nargs='?', help='output .raw (1024 bytes)')
    ap.add_argument('--demo', choices=['circle', 'square', 'triangle', 'cross', 'ring'])
    ap.add_argument('--noise', type=int, default=0)
    ap.add_argument('--shift', type=int, nargs=2, default=(0, 0), metavar=('DX', 'DY'))
    ap.add_argument('--radius', type=int, default=12)
    ap.add_argument('--invert', action='store_true')
    ap.add_argument('--threshold', type=int, default=0,
                    help='binarise at this level (0 = keep grey levels)')
    ap.add_argument('--no-auto-contrast', action='store_true')
    args = ap.parse_args()

    if args.demo:
        dst = args.dst or ('demo_%s.raw' % args.demo)
        img = render(args.demo, 16 + args.shift[0], 16 + args.shift[1],
                     args.radius, args.noise)
        label = args.demo
    else:
        if not args.src or not args.dst:
            ap.error('need SRC and DST (or use --demo)')
        w, h, ch, px = load_gray(args.src)
        img = resize_box(w, h, ch, px)
        if not args.no_auto_contrast:
            img = auto_contrast(img)
        dst = args.dst
        label = args.src

    if args.invert:
        img = bytearray(255 - v for v in img)
    if args.threshold:
        img = threshold(img, args.threshold)

    with open(dst, 'wb') as f:
        f.write(img)
    print('%s -> %s (%d bytes, %dx%d)' % (label, dst, len(img), W, H))
    print(preview(img))


if __name__ == '__main__':
    main()
