#!/usr/bin/env python3
"""Render the clawd mascot sprite to PNGs for the SketchyBar widget.

The 18x5 pixel-art bitmap is lifted verbatim from the Claude Usage Stick
firmware (github.com/oauramos/claude-usage-stick, src/ui.cpp CLAWD_ROWS):
a rounded head with two eyes (row-1 gaps at cols 5 & 12) and two pairs of feet.
Blink = fill the eye gaps. "dead" = gray with X eyes.

Outputs (transparent background): clawd-open.png, clawd-closed.png, clawd-dead.png.
Pure standard library (zlib) — no Pillow required.

Usage:
  gen-clawd.py [--out DIR] [--color RRGGBB] [--dead-color RRGGBB] [--cell-w N] [--cell-h N]
"""
import argparse
import os
import struct
import zlib

# 18-bit rows, MSB = leftmost column (col 0).
ROW0 = 0b000111111111111000
R1_OPEN = 0b000110111111011000  # eyes = the two gaps
R1_SHUT = 0b000111111111111000  # eyes filled (blink / dead)
ROW2 = 0b011111111111111110
ROW3 = 0b000111111111111000
ROW4 = 0b000010100001010000  # feet
EYE_COLS = (5, 12)
W_BITS, H_BITS = 18, 5


def rows(shut):
    return [ROW0, R1_SHUT if shut else R1_OPEN, ROW2, ROW3, ROW4]


def hex_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def write_png(path, w, h, rgba):
    """rgba: bytes of length w*h*4."""
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0
        raw.extend(rgba[y * w * 4:(y + 1) * w * 4])
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def render(path, shut, color, cell_w, cell_h, dead=False, dead_color=None):
    col = dead_color if dead else color
    w, h = W_BITS * cell_w, H_BITS * cell_h
    px = bytearray(w * h * 4)  # transparent

    def put(x, y, rgb):
        i = (y * w + x) * 4
        px[i:i + 4] = bytes((rgb[0], rgb[1], rgb[2], 255))

    rs = rows(shut or dead)
    for r, bits in enumerate(rs):
        for c in range(W_BITS):
            if bits & (1 << (W_BITS - 1 - c)):
                for dy in range(cell_h):
                    for dx in range(cell_w):
                        put(c * cell_w + dx, r * cell_h + dy, col)

    if dead:  # carve an X into each eye cell (row 1)
        for ec in EYE_COLS:
            x0, y0 = ec * cell_w, 1 * cell_h
            for k in range(min(cell_w, cell_h)):
                px[((y0 + k) * w + (x0 + k)) * 4 + 3] = 0
                px[((y0 + k) * w + (x0 + cell_w - 1 - k)) * 4 + 3] = 0
    write_png(path, w, h, px)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=".")
    ap.add_argument("--color", default="FFFFFF", help="clawd color (RRGGBB)")
    ap.add_argument("--dead-color", default="7B7D7B")
    ap.add_argument("--cell-w", type=int, default=4)
    ap.add_argument("--cell-h", type=int, default=8)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    color, dead = hex_rgb(a.color), hex_rgb(a.dead_color)
    render(os.path.join(a.out, "clawd-open.png"), False, color, a.cell_w, a.cell_h)
    render(os.path.join(a.out, "clawd-closed.png"), True, color, a.cell_w, a.cell_h)
    render(os.path.join(a.out, "clawd-dead.png"), False, color, a.cell_w, a.cell_h,
           dead=True, dead_color=dead)
    print(f"wrote clawd-open/closed/dead.png to {a.out} "
          f"({W_BITS * a.cell_w}x{H_BITS * a.cell_h}, color #{a.color})")


if __name__ == "__main__":
    main()
