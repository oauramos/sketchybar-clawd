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
#   CLAWD_STYLE        blocks (default) | braille | ascii
#   CLAWD_POSITION     right (default) | left | center
#   CLAWD_SHOW_LABELS  1 (default, show idle/working/waiting segments) | 0
#   CLAWD_FG           active/bright color   (default near-white)
#   CLAWD_MUTED        dimmed color          (default gray)
#   CLAWD_SEP_COLOR    separator dot color
#   CLAWD_ICON_FONT    mascot font  (needs a glyph-capable font for blocks/braille)
#   CLAWD_LABEL_FONT   segment label font
#   CLAWD_FRAME_MS     animation frame interval in ms (default 150)
#   CLAWD_BG / CLAWD_BORDER / CLAWD_BORDER_WIDTH / CLAWD_RADIUS / CLAWD_HEIGHT
#                      bracket (box) appearance
#   CLAWD_LABEL_IDLE / CLAWD_LABEL_WORK / CLAWD_LABEL_WAIT / CLAWD_SEP
#                      segment text and separator glyph
clawd_load_config() {
  CLAWD_STYLE="${CLAWD_STYLE:-blocks}"
  CLAWD_POSITION="${CLAWD_POSITION:-right}"
  CLAWD_SHOW_LABELS="${CLAWD_SHOW_LABELS:-1}"

  CLAWD_FG="${CLAWD_FG:-0xfff5f5f7}"
  CLAWD_MUTED="${CLAWD_MUTED:-0xff8e8e93}"
  CLAWD_SEP_COLOR="${CLAWD_SEP_COLOR:-0xff5a5a5e}"

  CLAWD_ICON_FONT="${CLAWD_ICON_FONT:-Hack Nerd Font:Bold:16.0}"
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
  # *inside* a frame). idle/wait are single static frames.
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
    blocks | *)
      CLAWD_STYLE="blocks"
      CLAWD_IDLE="▐▛██▜▌"
      CLAWD_WAIT="▝▛██▜▘"
      CLAWD_WORK="▐▛██▜▌ ▝▜██▛▘ ▐▟██▙▌ ▝▜██▛▘"
      ;;
  esac
}
