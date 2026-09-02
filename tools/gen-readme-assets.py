#!/usr/bin/env python3
"""Render the README's images from the widget's own sprite art.

Everything the README shows is generated here from `gen-clawd.py` output, so the
pictures can never drift from the mascot the widget actually draws: re-run this
after changing the sprite and the docs catch up.

Outputs (into assets/):
  clawd.png   the herd strip — one clawd per session, badges and all
  states.png  labelled reference: working / waiting / idle / error
  demo.gif    the same herd animated: a prompt lands, agents spawn, one asks

Every image is drawn on an opaque dark card, so a near-white mascot stays
visible on GitHub's light theme as well as its dark one.

Needs Pillow (`pip install pillow`) — unlike gen-clawd.py, which is stdlib-only
because the widget itself depends on it at runtime. This one is a docs tool.

Usage:  tools/gen-readme-assets.py [--out DIR]
"""
import argparse
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
GEN = os.path.join(HERE, "gen-clawd.py")

# The palette the README documents as the example theme (and the one the author
# runs): orange at work, gray asleep, near-white when it needs you.
WORK = "ef7139"
IDLE = "888888"
WAIT = "f5f5f7"
DEAD = "7b7d7b"

CARD = (28, 28, 30, 255)  # graphite card, ~ the bar's frosted box
EDGE = (72, 72, 74, 255)  # subtle gray border
ALARM = (217, 119, 87, 255)  # Claude orange — the "come back to me" border
TEXT = (245, 245, 247, 255)
MUTED = (152, 152, 157, 255)

# Sprite art is 72x48; every use upscales it by a whole number so the pixels
# stay square-edged (NEAREST) instead of going soft.
BIG, SMALL = 3, 2  # 216x144 for the strip, 144x96 for the state cards

FONTS = [
    os.path.expanduser("~/Library/Fonts/HackNerdFont-Bold.ttf"),
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
]


def font(size):
    for path in FONTS:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def sprites(cache, color):
    """Render every pose in `color` once, and return {pose: RGBA image}."""
    out = os.path.join(cache, color)
    if not os.path.isdir(out):
        subprocess.run(
            [sys.executable, GEN, "--out", out, "--color", color, "--dead-color", DEAD],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    poses = {}
    for name in os.listdir(out):
        if name.endswith(".png"):
            im = Image.open(os.path.join(out, name)).convert("RGBA")
            poses[name[len("clawd-") : -len(".png")]] = im
    return poses


def at(sprite, scale):
    return sprite.resize((sprite.width * scale, sprite.height * scale), Image.NEAREST)


def card(w, h, radius=54, border=EDGE, width=6):
    """A rounded graphite card — the bar's bracket, blown up."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle(
        [0, 0, w - 1, h - 1], radius=radius, fill=CARD, outline=border, width=width
    )
    return im


def paste_clawd(canvas, sprite, cx, cy, agents=0, ask=False):
    """Drop one clawd centred on (cx, cy), wearing the badges it has earned.

    The widget hangs both badges over the mascot's head — the running-agent
    count on the left, the "needs you" mark on the right — so they do here too.
    """
    x, y = cx - sprite.width // 2, cy - sprite.height // 2
    canvas.alpha_composite(sprite, (x, y))
    if not (agents or ask):
        return
    d = ImageDraw.Draw(canvas)
    f = font(max(14, int(sprite.height * 0.34)))
    top = y - int(sprite.height * 0.04)  # just clear of the head
    if agents:
        d.text((x + int(sprite.width * 0.06), top), f"{agents}" if agents <= 9 else "9+", font=f, fill=TEXT)
    if ask:
        d.text((x + int(sprite.width * 0.80), top), "?", font=f, fill=TEXT)


def herd_strip(pose_specs, sp, width=1120, height=270, alarm=False):
    """The widget itself: a card holding one clawd per session."""
    im = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    im.alpha_composite(card(width, height, border=ALARM if alarm else EDGE))
    n = len(pose_specs)
    for i, spec in enumerate(pose_specs):
        cx = int(width * (i + 0.5) / n)
        paste_clawd(
            im,
            at(sp[spec["color"]][spec["pose"]], BIG),
            cx,
            height // 2 + 22,  # sit low enough to leave the badges room
            agents=spec.get("agents", 0),
            ask=spec.get("ask", False),
        )
    return im


def build_hero(sp, out):
    """assets/clawd.png — four sessions, four moods, at a glance."""
    strip = herd_strip(
        [
            {"color": WORK, "pose": "hammer-down"},
            {"color": WORK, "pose": "hammer-up", "agents": 3},
            {"color": IDLE, "pose": "sleep"},
            {"color": WAIT, "pose": "wait", "ask": True},
        ],
        sp,
        alarm=True,
    )
    strip.save(os.path.join(out, "clawd.png"))


def build_states(sp, out):
    """assets/states.png — the same four, captioned for a first-time reader."""
    cells = [
        (WORK, "hammer-down", "working", "you hit enter", 0, False),
        (WORK, "hammer-up", "+ agents", "3 subagents", 3, False),
        (WAIT, "wait", "waiting", "it needs you", 0, True),
        (IDLE, "sleep", "idle", "turn finished", 0, False),
        (IDLE, "dead", "error", "the turn failed", 0, False),
    ]
    cw, ch, gap = 300, 330, 20
    w = cw * len(cells) + gap * (len(cells) - 1)
    im = Image.new("RGBA", (w, ch), (0, 0, 0, 0))
    title, sub = font(38), font(28)
    for i, (color, pose, name, note, agents, ask) in enumerate(cells):
        x = i * (cw + gap)
        im.alpha_composite(card(cw, ch, radius=40, width=4), (x, 0))
        paste_clawd(im, at(sp[color][pose], SMALL), x + cw // 2, 130, agents=agents, ask=ask)
        d = ImageDraw.Draw(im)
        for text, f, y, fill in ((name, title, 214, TEXT), (note, sub, 264, MUTED)):
            tw = d.textbbox((0, 0), text, font=f)[2]
            d.text((x + (cw - tw) // 2, y), text, font=f, fill=fill)
    im.save(os.path.join(out, "states.png"))


def build_demo(sp, out):
    """assets/demo.gif — a turn, start to finish, in about four seconds."""
    W, H = 1120, 270

    def frame(specs, alarm=False):
        im = Image.new("RGBA", (W, H), (18, 18, 20, 255))
        im.alpha_composite(herd_strip(specs, sp, W, H, alarm=alarm))
        return im.convert("P", palette=Image.ADAPTIVE, colors=64)

    sleep = {"color": IDLE, "pose": "sleep"}
    frames, delays = [], []

    def beat(specs, ms, alarm=False):
        frames.append(frame(specs, alarm))
        delays.append(ms)

    # everyone asleep -> a prompt lands on the first one -> it hammers
    beat([sleep, sleep, sleep], 900)
    for _ in range(3):
        for pose in ("hammer-up", "hammer-down"):
            beat([{"color": WORK, "pose": pose}, sleep, sleep], 170)
    # it fans out to subagents: the badge counts up while it keeps working
    for n in (1, 2, 3):
        for pose in ("hammer-up", "hammer-down"):
            beat([{"color": WORK, "pose": pose, "agents": n}, sleep, sleep], 260)
    # a second session hits a permission prompt: "?" + the box goes orange
    for _ in range(2):
        for pose in ("hammer-up", "hammer-down"):
            beat(
                [
                    {"color": WORK, "pose": pose, "agents": 3},
                    {"color": WAIT, "pose": "wait", "ask": True},
                    sleep,
                ],
                300,
                alarm=True,
            )
    beat(
        [
            {"color": WORK, "pose": "hammer-down", "agents": 3},
            {"color": WAIT, "pose": "wait", "ask": True},
            sleep,
        ],
        1100,
        alarm=True,
    )
    # answered, agents done, back to sleep
    beat([sleep, sleep, sleep], 1200)

    frames[0].save(
        os.path.join(out, "demo.gif"),
        save_all=True,
        append_images=frames[1:],
        duration=delays,
        loop=0,
        optimize=True,
        disposal=2,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(REPO, "assets"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    with tempfile.TemporaryDirectory() as cache:
        sp = {c: sprites(cache, c) for c in (WORK, IDLE, WAIT)}
        build_hero(sp, args.out)
        build_states(sp, args.out)
        build_demo(sp, args.out)
    for name in ("clawd.png", "states.png", "demo.gif"):
        path = os.path.join(args.out, name)
        print(f"  {name:12} {os.path.getsize(path) / 1024:6.0f} KB")


if __name__ == "__main__":
    main()
