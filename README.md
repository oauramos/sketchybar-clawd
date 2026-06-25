# sketchybar-clawd

A tiny [SketchyBar](https://github.com/FelixKratz/SketchyBar) widget that puts a little **herd of
clawds** in your macOS menu bar — **one clawd per running [Claude Code](https://claude.com/claude-code)
session**, each *acting out* what that session is doing. A glance tells you how many sessions you
have and whether any of them needs you.

<p align="center">
  <img src="assets/clawd.png" alt="one clawd per Claude Code session, each acting out its state" width="320">
</p>

Each clawd plays its session's state — and can be colored per state:

| clawd | State | When |
|-------|-------|------|
| 🔨 **hammers** (orange) | **working** | from the moment you submit a prompt until the turn ends |
| ❓ **open-eyed + a "?" badge** (white) | **waiting** | the session needs you — a permission prompt or dialog |
| 💤 **asleep, `-_-` + zzz** (gray) | **idle** | at rest / the turn finished |
| 💀 **keels over, X-eyes** | **error** | the turn ended in an API error (`StopFailure`) |

Whenever **any** session is waiting on you, the whole box border glows **orange** — a peripheral-
vision "come back to me" alarm. The herd is sorted by start time and capped at `CLAWD_HERD_MAX`
clawds, then collapses to a `+K` counter. Sessions appear on `SessionStart`, vanish on `SessionEnd`.

With **no sessions at all**, a single neutral-white clawd just **blinks** (eyes open/closed, no
hammer, no raised arms, no zzz) — a quiet "nobody home, start me" call to action. Tune it with
`CLAWD_BLINK_MS`.

Prefer a single mascot? Set **`CLAWD_MODE=hero`** for one clawd reflecting your *most-urgent*
session (`waiting > error > working > idle`) plus a compact glyph strip — `○` idle, `●` working,
`◐` waiting, `✗` error — one glyph per session.

The mascot is the pixel-art clawd from the **[Claude Usage Stick](https://github.com/oauramos/claude-usage-stick)**
firmware (here 18×6, with a prop band for the mallet / raised arms / zzz). It works standalone too —
drive a session yourself with the hook script.

> **Want to measure your usage, too?** sketchybar-clawd shows what your sessions are *doing*; for how
> much Claude you're actually *burning through*, its sibling project
> **[claude-usage-stick](https://github.com/oauramos/claude-usage-stick)** is a tiny hardware dongle
> (starring the very same clawd) that shows your live Claude usage on a little screen. They pair nicely.

## Requirements

- **macOS** with [SketchyBar](https://github.com/FelixKratz/SketchyBar) installed and running.
- **`jq`** — used to read the notification type and to merge the hooks (`brew install jq`).
  Optional if you don't use the Claude Code hooks.
- **Claude Code** — for the hooks that drive the states automatically.

The default `image` mascot ships as ready-made PNGs and needs no extra fonts. (The optional
glyph styles — `blocks` / `braille` — want a [Nerd Font](https://www.nerdfonts.com/) like
`Hack Nerd Font`; `ascii` needs nothing.)

## Install

```sh
git clone https://github.com/oauramos/sketchybar-clawd.git
cd sketchybar-clawd
./install.sh
```

The installer will:

1. Copy the widget into `~/.config/sketchybar/clawd/`.
2. Offer to add one line to your `sketchybarrc`:
   ```sh
   source "$CONFIG_DIR/clawd/clawd.widget.sh"
   ```
3. Offer to merge the Claude Code hooks into `~/.claude/settings.json`.
4. Reload SketchyBar.

It is idempotent, backs up any file before changing it, and never overwrites your config.
If your `sketchybarrc` is read-only (e.g. managed by Nix/home-manager), it prints the line
for you to add declaratively instead of editing it.

Useful flags: `--no-hooks`, `--with-hooks`, `--yes` (non-interactive), `--config-dir DIR`,
`--link` (symlink instead of copy, for development), `--print-only` (dry run).

### Manual install

```sh
cp -r src ~/.config/sketchybar/clawd
chmod +x ~/.config/sketchybar/clawd/*.sh
echo 'source "$CONFIG_DIR/clawd/clawd.widget.sh"' >> ~/.config/sketchybar/sketchybarrc
sketchybar --reload
# then, for the automatic states:
hooks/install-hooks.sh --hook ~/.config/sketchybar/clawd/clawd.hook.sh
```

## Configuration

Export any of these **before** the `source` line in your `sketchybarrc`:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAWD_MODE` | `herd` | `herd` (one clawd per session) or `hero` (one most-urgent mascot + glyph strip) |
| `CLAWD_HERD_MAX` | `6` | Herd: clawds shown before collapsing to `+K` |
| `CLAWD_HERD_MS` | `180` | Herd: animation frame interval (ms) |
| `CLAWD_STYLE` | `image` | Mascot: `image` (pixel-art sprite), or glyphs `blocks` / `braille` / `ascii` (glyphs force `hero`) |
| `CLAWD_POSITION` | `right` | Bar side: `left`, `center`, `right` |
| `CLAWD_IMG_SCALE` | `0.4` | Sprite scale (image mode) |
| `CLAWD_IMG_WIDTH` | `34` | Per-clawd item width in px (image mode) |
| `CLAWD_IMG_PAD_LEFT` | `0` | Left margin before the sprite (px) |
| `CLAWD_COLOR` | `ffffff` | Base sprite color `RRGGBB` — auto-recolors (needs `python3`) |
| `CLAWD_COLOR_WORK` / `CLAWD_COLOR_IDLE` / `CLAWD_COLOR_WAIT` | `$CLAWD_COLOR` | Per-state sprite colors (e.g. orange working, gray idle, white waiting) |
| `CLAWD_DEAD_COLOR` | `7b7d7b` | Color of the "dead"/error sprite |
| `CLAWD_SHOW_DOTS` | `1` | Hero mode: show the per-session glyph strip (`0` = mascot only) |
| `CLAWD_DOT_IDLE` / `CLAWD_DOT_WORK` / `CLAWD_DOT_WAIT` / `CLAWD_DOT_ERR` | `○` / `●` / `◐` / `✗` | Per-state strip glyphs |
| `CLAWD_STRIP_MAX` | `8` | Show at most N glyphs, then collapse to `+K` |
| `CLAWD_DOT_SEP` | `" "` | Separator between glyphs |
| `CLAWD_DOT_FONT` | `Hack Nerd Font:Bold:14.0` | Strip font (a Nerd/monospace font keeps `○ ● ◐ ✗` the same size) |
| `CLAWD_DOT_COLOR` | `$CLAWD_FG` | Strip color |
| `CLAWD_SESSION_TTL` | `28800` | Prune a session with no update for this many seconds (safety net) |
| `CLAWD_FG` | `0xfff5f5f7` | Foreground/accent color |
| `CLAWD_ICON_FONT` | `Hack Nerd Font:Bold:12.0` | Mascot font (glyph styles only) |
| `CLAWD_FRAME_MS` | `150` | Working (hammer) frame interval (ms) |
| `CLAWD_BLINK_MS` | `200` | No-session blink frame interval (ms) — exact in `hero`; `herd` blinks on the herd tick |
| `CLAWD_ASK_GLYPH` / `CLAWD_ASK_COLOR` / `CLAWD_ASK_FONT` / `CLAWD_ASK_YOFF` | `?` / `$CLAWD_FG` / `Hack Nerd Font:Bold:9.0` / `5` | Waiting "?" badge over the mascot's top-right |
| `CLAWD_BG` / `CLAWD_BORDER` / `CLAWD_BORDER_WIDTH` / `CLAWD_RADIUS` / `CLAWD_HEIGHT` | — | Box (bracket) appearance |
| `CLAWD_BORDER_WAIT` | `0xffd97757` | Box border color while a session is **waiting** (the "come back" alarm) |

Example — bigger sprite on the left:

```sh
export CLAWD_POSITION=left
export CLAWD_IMG_SCALE=0.8
source "$CONFIG_DIR/clawd/clawd.widget.sh"
```

Example — match a monochrome bar (near-white clawd in a graphite box):

```sh
export CLAWD_COLOR=f5f5f7          # recolors the sprite to your foreground
export CLAWD_BG=0xbf1c1c1e         # match your box fill
export CLAWD_BORDER=0xff48484a     # and border
export CLAWD_RADIUS=9
source "$CONFIG_DIR/clawd/clawd.widget.sh"
```

Example — color-code the states (orange working, gray idle, white waiting):

```sh
export CLAWD_COLOR_WORK=ef7139   # the Claude-orange clawd, hammering
export CLAWD_COLOR_IDLE=888888   # dim gray, asleep
export CLAWD_COLOR_WAIT=f5f5f7   # white, with a "?" badge
source "$CONFIG_DIR/clawd/clawd.widget.sh"
```

Each color renders recolored frames once (cached under `~/.cache/sketchybar-clawd/`) using the
bundled `gen-clawd.py`; the cache key includes an art version, so sprite-art upgrades regenerate
automatically. The shipped default is a neutral white that suits most bars (set `CLAWD_COLOR=D97757`
for the classic Claude orange).

### The mascot sprite

The sprite is an 18×6 pixel-art clawd (rounded head, two eyes, four feet, plus a one-row prop
band on top) rendered to one PNG per pose: `clawd-open` / `clawd-closed` (blink), `clawd-dead`
(error, X-eyes), `clawd-hammer-up` / `clawd-hammer-down` (working), `clawd-wait`
(waiting — a plain open-eyed body; the widget overlays a "?" badge), and `clawd-sleep`
(idle — `-_-` dashed eyes + a rising `zzz`). To recolor or
resize them, regenerate every pose with the bundled generator (pure Python 3, no dependencies):

```sh
python3 tools/gen-clawd.py --out ~/.config/sketchybar/clawd/frames --color 88c0d0 --cell-w 4 --cell-h 8
# or just one pose: --pose hammer-up
```

Prefer text? Set `CLAWD_STYLE=blocks` (or `braille` / `ascii`) for a glyph mascot instead.

## Claude Code hooks

`hooks/install-hooks.sh` merges this into `~/.claude/settings.json` (existing keys and any
other hooks are preserved; re-running never duplicates):

Each hook carries a `session_id` on stdin, so a session is tracked individually:

| Hook | Fires | This session → |
|------|-------|----------------|
| `SessionStart` | A session begins/resumes | appears as `idle` |
| `UserPromptSubmit` | You submit a prompt | `working` |
| `Stop` | Turn finishes | `idle` |
| `StopFailure` | Turn ends in an API error | `error` (clawd keels over) |
| `Notification` | `permission_prompt` / `elicitation_dialog` → `waiting`; `idle_prompt` → `idle` | `waiting` / `idle` |
| `SessionEnd` | A session ends | glyph removed |

`working` starts at `UserPromptSubmit` (not `PreToolUse`) so the hero reacts the instant
you hit enter, even on text-only replies. See `hooks/settings.snippet.json` for the raw block
if you'd rather paste it by hand.

Install for a single project instead of globally: `hooks/install-hooks.sh --project`.
Remove the hooks: `hooks/install-hooks.sh --remove`.

## How it works

- Each hook calls `clawd.hook.sh`, which records that session's state in
  `~/.cache/sketchybar-clawd/sessions/<session_id>` and fires the `claude_state` event.
- On that event `clawd.plugin.sh` reads every session file and renders one of two layouts:
  - **herd** (default): a fixed pool of slot items (`clawd.s0…`), one shown per session (sorted by
    start time, capped at `CLAWD_HERD_MAX` then `+K`), each set to its session's pose/color.
  - **hero**: tallies the states, picks the single most-urgent one (`waiting > error > working >
    idle`) for the mascot, and writes the urgency-sorted glyph strip on the `clawd.sessions` label.
  - Either way it paints the `clawd_box` border orange whenever any session is waiting, and overlays
    a "?" badge (an item label) on each waiting clawd.
- The animated pose (working) is played by a small background worker that swaps
  `background.image` between frames — a worker is used because SketchyBar's `update_freq` is
  whole-second, too coarse for smooth motion. The hero worker re-reads `anim.state` each frame; the
  herd worker advances every animated clawd on a shared tick from `multi.state`. Workers are tracked
  by PID files (with a command-line guard against PID reuse) and stopped when nothing is animating.
- If a session is killed without `SessionEnd` firing, its file is pruned after
  `CLAWD_SESSION_TTL` as a safety net.

## Uninstall

```sh
./uninstall.sh
```

Removes the widget files, the `source` line, and the hooks (backups kept). Flags:
`--keep-hooks`, `--config-dir DIR`, `--yes`.

## Troubleshooting

- **Mascot doesn't show (image mode):** make sure `frames/*.png` exist next to the scripts
  (`ls ~/.config/sketchybar/clawd/frames`) and bump `CLAWD_IMG_WIDTH` if it looks clipped.
- **Mascot shows boxes/▯ (glyph styles):** the font lacks the glyphs. Use the default
  `CLAWD_STYLE=image`, point `CLAWD_ICON_FONT` at a Nerd Font, or use `CLAWD_STYLE=ascii`.
- **No dots / nothing changes when Claude runs:** confirm the hooks are installed
  (`jq .hooks ~/.claude/settings.json`) and `clawd.hook.sh` is executable. A session that
  started *before* the hooks were installed won't appear until you relaunch `claude`. Test the
  bar side directly: `echo '{"session_id":"test"}' | ~/.config/sketchybar/clawd/clawd.hook.sh working`.
- **A dot stuck on `●`:** interrupting Claude (Esc) doesn't fire `Stop`; the next `idle_prompt`
  notification recovers it, or it's pruned after `CLAWD_SESSION_TTL`. Reset all now:
  `rm -f ~/.cache/sketchybar-clawd/sessions/* && sketchybar --trigger claude_state`.
- **A stray animation process:** `pkill -f "clawd.plugin.sh __clawd_"` (matches both the hero and
  herd workers; a reload also clears them).

## License

MIT — see [LICENSE](LICENSE).
