#!/bin/sh
# clawd.lib.sh — shared config defaults and mascot frames for sketchybar-clawd.
#
# Sourced by both clawd.widget.sh (from your sketchybarrc) and clawd.plugin.sh
# (the item script the SketchyBar daemon spawns). Pure definitions + functions,
# no side effects on source. POSIX sh — no bashisms.
#
# Every CLAWD_* variable defined here is consumed by the scripts that source this
# file, so silence "appears unused" for the whole file.
# shellcheck disable=SC2034

# Where mutable runtime state lives (PID file + resolved config snapshot).
clawd_state_dir() {
  printf '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar-clawd"
}

# Resolve every CLAWD_* setting from the environment, applying defaults, and
# select the mascot frames for the chosen style. Idempotent — safe to call again
# after sourcing an overrides file.
#
# Knobs (all overridable via environment before sourcing clawd.widget.sh):
#   CLAWD_STYLE        image (default, the pixel-art sprite) | blocks | braille | ascii
#   CLAWD_POSITION     right (default) | left | center
#   CLAWD_SHOW_LABELS  1 (default, show idle/working/waiting segments) | 0
#   CLAWD_IMG_SCALE    image-mode sprite scale (default 0.4)
#   CLAWD_IMG_WIDTH    image-mode item width in px (default 34)
#   CLAWD_COLOR        sprite color RRGGBB (default neutral white; auto-recolors via
#                      the bundled generator — needs python3 — and caches the result)
#   CLAWD_DEAD_COLOR   color for the "dead"/error sprite (default 7b7d7b gray)
#   CLAWD_FRAMES_DIR   dir holding clawd-open/closed/dead.png (set automatically)
#   CLAWD_FG           active/bright color   (default near-white)
#   CLAWD_MUTED        dimmed color          (default gray)
#   CLAWD_SEP_COLOR    separator dot color
#   CLAWD_ICON_FONT    mascot font  (glyph styles only; needs a glyph-capable font)
#   CLAWD_LABEL_FONT   segment label font
#   CLAWD_FRAME_MS     animation frame interval in ms (default 150)
#   CLAWD_BG / CLAWD_BORDER / CLAWD_BORDER_WIDTH / CLAWD_RADIUS / CLAWD_HEIGHT
#                      bracket (box) appearance
#   CLAWD_LABEL_IDLE / CLAWD_LABEL_WORK / CLAWD_LABEL_WAIT / CLAWD_SEP
#                      segment text and separator glyph
clawd_load_config() {
  CLAWD_STYLE="${CLAWD_STYLE:-image}"
  CLAWD_POSITION="${CLAWD_POSITION:-right}"
  CLAWD_SHOW_LABELS="${CLAWD_SHOW_LABELS:-1}"

  # image mode: the clawd pixel-art sprite (PNG via background.image)
  CLAWD_FRAMES_DIR="${CLAWD_FRAMES_DIR:-}"
  CLAWD_IMG_SCALE="${CLAWD_IMG_SCALE:-0.4}"
  CLAWD_IMG_WIDTH="${CLAWD_IMG_WIDTH:-34}"
  CLAWD_SHIPPED_COLOR="ffffff"                # color of the committed src/frames
  CLAWD_SHIPPED_DEAD="7b7d7b"
  CLAWD_COLOR="${CLAWD_COLOR:-$CLAWD_SHIPPED_COLOR}"    # sprite color (RRGGBB)
  CLAWD_DEAD_COLOR="${CLAWD_DEAD_COLOR:-$CLAWD_SHIPPED_DEAD}"

  CLAWD_FG="${CLAWD_FG:-0xfff5f5f7}"
  CLAWD_MUTED="${CLAWD_MUTED:-0xff8e8e93}"
  CLAWD_SEP_COLOR="${CLAWD_SEP_COLOR:-0xff5a5a5e}"

  CLAWD_ICON_FONT="${CLAWD_ICON_FONT:-Hack Nerd Font:Bold:12.0}"
  CLAWD_LABEL_FONT="${CLAWD_LABEL_FONT:-SF Pro:Semibold:13.0}"

  CLAWD_FRAME_MS="${CLAWD_FRAME_MS:-150}"

  CLAWD_BG="${CLAWD_BG:-0x22ffffff}"
  CLAWD_BORDER="${CLAWD_BORDER:-0x33ffffff}"
  CLAWD_BORDER_WIDTH="${CLAWD_BORDER_WIDTH:-1}"
  CLAWD_RADIUS="${CLAWD_RADIUS:-8}"
  CLAWD_HEIGHT="${CLAWD_HEIGHT:-26}"

  CLAWD_LABEL_IDLE="${CLAWD_LABEL_IDLE:-idle}"
  CLAWD_LABEL_WORK="${CLAWD_LABEL_WORK:-working}"
  CLAWD_LABEL_WAIT="${CLAWD_LABEL_WAIT:-waiting}"
  CLAWD_SEP="${CLAWD_SEP:-·}"

  # Mascot frames. CLAWD_WORK is a space-separated list of frames (no spaces
  # *inside* a frame). idle/wait are single static frames; in image mode the
  # frames are PNG paths, otherwise they are glyph strings.
  case "$CLAWD_STYLE" in
    braille)
      CLAWD_IDLE="⡏⣿⣹"
      CLAWD_WAIT="⢇⣿⡸"
      CLAWD_WORK="⡏⣿⣹ ⢏⣿⡹ ⣾⣿⣷ ⢏⣿⡹"
      ;;
    ascii)
      CLAWD_IDLE="(o.o)"
      CLAWD_WAIT="(o.?)"
      CLAWD_WORK="(o.o) (-.o) (o.o) (o.-)"
      ;;
    blocks)
      # A small sitting clawd with arms (glyph fallback).
      CLAWD_IDLE="▖▟██▙▗"
      CLAWD_WAIT="▘▟██▙▝"
      CLAWD_WORK="▖▟██▙▗ ▌▟██▙▐ ▘▟██▙▝ ▌▟██▙▐"
      ;;
    image | *)
      # Default: the real clawd pixel-art sprite (PNG via background.image).
      # working = blink (mostly eyes-open with a quick shut); idle/waiting = open.
      CLAWD_STYLE="image"
      _f="${CLAWD_FRAMES_DIR}"
      CLAWD_IDLE="$_f/clawd-open.png"
      CLAWD_WAIT="$_f/clawd-open.png"
      CLAWD_DEAD="$_f/clawd-dead.png"
      CLAWD_WORK="$_f/clawd-open.png $_f/clawd-open.png $_f/clawd-open.png $_f/clawd-open.png $_f/clawd-open.png $_f/clawd-closed.png"
      ;;
  esac
}
