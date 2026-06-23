#!/usr/bin/env python3
"""Render the clawd mascot sprite to PNGs for the SketchyBar widget.

The 18x5 pixel-art bitmap is lifted verbatim from the Claude Usage Stick
firmware (github.com/oauramos/claude-usage-stick, src/ui.cpp CLAWD_ROWS):
a rounded head with two eyes (row-1 gaps at cols 5 & 12) and two pairs of feet.
Blink = fill the eye gaps. "dead" = gray with X eyes.

State poses (for the per-session "hero" mascot) add a one-row prop band ABOVE
the body, so the canvas is 18x6 (body occupies rows 1..5, row 0 is props):
  hammer-up / hammer-down  a 2x2 mallet head that travels top->bottom (working)
  wait / wait-dim          both arms thrown up; -dim is the dimmer pulse frame
  sleep                    eyes shut + a rising "zzz" trail (idle)

Outputs (transparent background) — by default every pose:
  clawd-open, clawd-closed, clawd-dead, clawd-hammer-up, clawd-hammer-down,
  clawd-wait, clawd-wait-dim, clawd-sleep  (all .png).
Pure standard library (zlib) — no Pillow required.

Usage:
  gen-clawd.py [--out DIR] [--color RRGGBB] [--dead-color RRGGBB]
               [--cell-w N] [--cell-h N] [--pose NAME]
"""
import argparse
import os
import struct
import zlib

# 18-bit body rows, MSB = leftmost column (col 0). Body sits at grid rows 1..5;
# grid row 0 is the prop band (raised arms / mallet head / zzz).
ROW0 = 0b000111111111111000
R1_OPEN = 0b000110111111011000  # eyes = the two gaps
R1_SHUT = 0b000111111111111000  # eyes filled (blink / dead / sleep)
ROW2 = 0b011111111111111110
ROW3 = 0b000111111111111000
ROW4 = 0b000010100001010000  # feet
EYE_COLS = (5, 12)
W_BITS, GRID_H = 18, 6
BODY_Y = 1                     # body's top row in the 6-row grid
EYE_GRID_Y = BODY_Y + 1        # eyes live on body row 1 -> grid row 2
DIM_ALPHA = 110                # the "-dim" pulse frame

# Per-pose prop pixels as (col, grid_row), eye state, and flags.
POSES = {
    "open":        {"shut": False, "props": []},
    "closed":      {"shut": True,  "props": []},
    "dead":        {"shut": True,  "props": [], "dead": True},
    # mallet head (2x2) high, handle down to the shoulder
    "hammer-up":   {"shut": False, "props": [(15, 0), (16, 0), (15, 1), (16, 1), (15, 2)]},
    # mallet head down by the feet + a spark recoil up high
    "hammer-down": {"shut": False, "props": [(15, 4), (16, 4), (15, 5), (16, 5), (16, 2)]},
    # both arms thrown up: "come back!"
    "wait":        {"shut": False, "props": [(3, 0), (4, 0), (13, 0), (14, 0)]},
    "wait-dim":    {"shut": False, "props": [(3, 0), (4, 0), (13, 0), (14, 0)], "dim": True},
    # dashed "-_-" eyes + a rising zzz trail
    "sleep":       {"shut": True,  "dash": True, "props": [(14, 3), (15, 2), (16, 1), (17, 0)]},
}
ALL_POSES = list(POSES)


def body_rows(shut):
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


def render(path, name, color, cell_w, cell_h, dead_color=None):
    spec = POSES[name]
    dead = spec.get("dead", False)
    col = dead_color if (dead and dead_color) else color
    alpha = DIM_ALPHA if spec.get("dim") else 255
    w, h = W_BITS * cell_w, GRID_H * cell_h
    px = bytearray(w * h * 4)  # transparent

    def put(cx, cy):
        for dy in range(cell_h):
            for dx in range(cell_w):
                i = ((cy * cell_h + dy) * w + (cx * cell_w + dx)) * 4
                px[i:i + 4] = bytes((col[0], col[1], col[2], alpha))

    for r, bits in enumerate(body_rows(spec["shut"])):
        for c in range(W_BITS):
            if bits & (1 << (W_BITS - 1 - c)):
                put(c, BODY_Y + r)
    for (cx, cy) in spec["props"]:
        put(cx, cy)

    if dead:  # carve an X into each eye cell
        for ec in EYE_COLS:
            x0, y0 = ec * cell_w, EYE_GRID_Y * cell_h
            for k in range(min(cell_w, cell_h)):
                px[((y0 + k) * w + (x0 + k)) * 4 + 3] = 0
                px[((y0 + k) * w + (x0 + cell_w - 1 - k)) * 4 + 3] = 0
    if spec.get("dash"):  # carve a horizontal "-" slit into each eye cell (sleepy -_-)
        dash_h = max(1, cell_h // 3)
        y0 = EYE_GRID_Y * cell_h + (cell_h - dash_h) // 2
        for ec in EYE_COLS:
            x0 = ec * cell_w
            for dy in range(dash_h):
                for dx in range(cell_w):
                    px[((y0 + dy) * w + (x0 + dx)) * 4 + 3] = 0
    write_png(path, w, h, px)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=".")
    ap.add_argument("--color", default="FFFFFF", help="clawd color (RRGGBB)")
    ap.add_argument("--dead-color", default="7B7D7B")
    ap.add_argument("--cell-w", type=int, default=4)
    ap.add_argument("--cell-h", type=int, default=8)
    ap.add_argument("--pose", choices=ALL_POSES, help="render only this pose (default: all)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    color, dead = hex_rgb(a.color), hex_rgb(a.dead_color)
    names = [a.pose] if a.pose else ALL_POSES
    for name in names:
        render(os.path.join(a.out, f"clawd-{name}.png"), name, color,
               a.cell_w, a.cell_h, dead_color=dead)
    print(f"wrote {len(names)} pose(s) to {a.out} "
          f"({W_BITS * a.cell_w}x{GRID_H * a.cell_h}, color #{a.color}): "
          f"{', '.join(names)}")


if __name__ == "__main__":
    main()
