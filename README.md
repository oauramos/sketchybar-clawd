# sketchybar-clawd

A tiny [SketchyBar](https://github.com/FelixKratz/SketchyBar) widget: a **clawd**
mascot + status pills that mirror what [Claude Code](https://claude.com/claude-code)
is doing right now — **working**, **waiting** for you, or **idle**.

<p align="center">
  <img src="assets/clawd.png" alt="clawd widget showing working / waiting / idle states" width="280">
</p>

The mascot is the **clawd pixel-art sprite** (the same 18×5 bitmap as the
[Claude Usage Stick](https://github.com/oauramos/claude-usage-stick) firmware), and the
active state lights up while the rest dim — the same highlight style as SketchyBar
workspace pills. When Claude is working, clawd **blinks**.

| State | When | Mascot | Pill lit |
|-------|------|--------|----------|
| **working** | From the moment you submit a prompt until the turn ends | blinks | `working` |
| **waiting** | Claude needs you — a permission prompt or a dialog | eyes open | `waiting` |
| **idle** | Turn finished / nothing running | eyes open | `idle` |

It works as a standalone widget too: trigger the states yourself with
`sketchybar --trigger claude_state STATE=working` from anything.

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
| `CLAWD_STYLE` | `image` | Mascot: `image` (pixel-art sprite), or glyphs `blocks` / `braille` / `ascii` |
| `CLAWD_POSITION` | `right` | Bar side: `left`, `center`, `right` |
| `CLAWD_SHOW_LABELS` | `1` | Show the `idle · working · waiting` pills (`0` = mascot only) |
| `CLAWD_IMG_SCALE` | `0.4` | Sprite scale (image mode) |
| `CLAWD_IMG_WIDTH` | `34` | Mascot item width in px (image mode) |
| `CLAWD_FG` | `0xfff5f5f7` | Active/bright pill color |
| `CLAWD_MUTED` | `0xff8e8e93` | Dimmed (inactive) pill color |
| `CLAWD_SEP_COLOR` | `0xff5a5a5e` | Separator dot color |
| `CLAWD_LABEL_FONT` | `SF Pro:Semibold:13.0` | Pill label font |
| `CLAWD_ICON_FONT` | `Hack Nerd Font:Bold:12.0` | Mascot font (glyph styles only) |
| `CLAWD_FRAME_MS` | `150` | Animation frame interval (ms) |
| `CLAWD_BG` / `CLAWD_BORDER` / `CLAWD_BORDER_WIDTH` / `CLAWD_RADIUS` / `CLAWD_HEIGHT` | — | Box (bracket) appearance |
| `CLAWD_LABEL_IDLE` / `CLAWD_LABEL_WORK` / `CLAWD_LABEL_WAIT` / `CLAWD_SEP` | `idle` / `working` / `waiting` / `·` | Pill text & separator |

Example — bigger sprite on the left, no pills:

```sh
export CLAWD_POSITION=left
export CLAWD_SHOW_LABELS=0
export CLAWD_IMG_SCALE=0.8
source "$CONFIG_DIR/clawd/clawd.widget.sh"
```

### The mascot sprite

The sprite is an 18×5 pixel-art clawd (rounded head, two eyes, four feet) rendered to
`frames/clawd-open.png`, `clawd-closed.png` (blink), and `clawd-dead.png`. To recolor or
resize them, regenerate with the bundled generator (pure Python 3, no dependencies):

```sh
python3 tools/gen-clawd.py --out ~/.config/sketchybar/clawd/frames --color D97757 --cell-w 4 --cell-h 8
```

Prefer text? Set `CLAWD_STYLE=blocks` (or `braille` / `ascii`) for a glyph mascot instead.

## Claude Code hooks

`hooks/install-hooks.sh` merges this into `~/.claude/settings.json` (existing keys and any
other hooks are preserved; re-running never duplicates):

| Hook | Fires | → state |
|------|-------|---------|
| `UserPromptSubmit` | You submit a prompt | `working` |
| `Stop` | Claude finishes the turn | `idle` |
| `StopFailure` | Turn ends on an API error | `idle` |
| `Notification` | `permission_prompt` / `elicitation_dialog` → `waiting`; `idle_prompt` → `idle` | `waiting` / `idle` |

`working` starts at `UserPromptSubmit` (not `PreToolUse`) so the mascot reacts the instant
you hit enter, even on text-only replies. See `hooks/settings.snippet.json` for the raw block
if you'd rather paste it by hand.

Install for a single project instead of globally: `hooks/install-hooks.sh --project`.
Remove the hooks: `hooks/install-hooks.sh --remove`.

## How it works

- The hooks call `clawd.hook.sh <state>`, which fires a custom SketchyBar event:
  `sketchybar --trigger claude_state STATE=<state>`.
- The `clawd` item subscribes to `claude_state`; `clawd.plugin.sh` highlights the active pill
  and, while working, starts a small background worker that cycles the mascot frames (swapping
  `background.image` for the sprite) every `CLAWD_FRAME_MS`. A background worker is used because
  SketchyBar's `update_freq` is whole-second — too coarse for a smooth blink.
- The worker is tracked by a PID file in `~/.cache/sketchybar-clawd/` and stopped on every
  state change and on reload, so no animation process is ever left running.

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
- **Nothing changes when Claude runs:** confirm the hooks are installed
  (`jq .hooks ~/.claude/settings.json`) and that `clawd.hook.sh` is executable. Test the bar
  side directly: `sketchybar --trigger claude_state STATE=working`.
- **Mascot stuck on "working":** interrupting Claude (Esc) doesn't fire `Stop`; the next
  `idle_prompt` notification recovers it. To reset now: `sketchybar --trigger claude_state STATE=idle`.
- **A stray animation process:** `pkill -f "clawd.plugin.sh __clawd_anim__"` (a reload also
  clears it).

## License

MIT — see [LICENSE](LICENSE).
