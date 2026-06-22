#!/bin/sh
# clawd.lib.sh — shared config defaults, mascot frames, and per-session helpers
# for sketchybar-clawd.
#
# Sourced by both clawd.widget.sh (from your sketchybarrc) and clawd.plugin.sh
# (the item script the SketchyBar daemon spawns). Pure definitions + functions,
# no side effects on source. POSIX sh — no bashisms.
#
# Every CLAWD_* variable defined here is consumed by the scripts that source this
# file, so silence "appears unused" for the whole file.
# shellcheck disable=SC2034

# Mutable runtime state (sprite frame cache + per-session states + PID file).
clawd_state_dir() {
  printf '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar-clawd"
}
# One file per live Claude Code session: name = session_id, content = state.
clawd_sessions_dir() {
  printf '%s' "$(clawd_state_dir)/sessions"
}

# Map a session state to its dot glyph.
clawd_dot() {
  case "$1" in
    working) printf '%s' "$CLAWD_DOT_WORK" ;;
    waiting) printf '%s' "$CLAWD_DOT_WAIT" ;;
    *) printf '%s' "$CLAWD_DOT_IDLE" ;;
  esac
}

# Resolve every CLAWD_* setting from the environment, applying defaults, and
# select the mascot frames. Idempotent — safe to call again after sourcing an
# overrides file.
#
# Knobs (override via environment before sourcing clawd.widget.sh):
#   Mascot (the clawd icon on the left):
#     CLAWD_STYLE        image (default, pixel-art sprite) | blocks | braille | ascii
#     CLAWD_POSITION     right (default) | left | center
#     CLAWD_IMG_SCALE    sprite scale (default 0.4)        CLAWD_IMG_WIDTH  px (default 34)
#     CLAWD_IMG_PAD_LEFT left margin before the sprite, px (default 0)
#     CLAWD_COLOR        sprite color RRGGBB (default neutral white; auto-recolors
#                        via the bundled generator — needs python3 — and caches it)
#     CLAWD_DEAD_COLOR   "dead"/error sprite color (default 7b7d7b)
#     CLAWD_FRAME_MS     blink frame interval ms (default 150)
#     CLAWD_ICON_FONT    mascot font (glyph styles only)
#   Per-session status dots (one per running Claude Code session):
#     CLAWD_SHOW_DOTS    1 (default) | 0 (mascot only)
#     CLAWD_DOT_IDLE / CLAWD_DOT_WORK / CLAWD_DOT_WAIT   glyphs (○ ● ◐)
#     CLAWD_DOT_SEP      separator between dots (default " ")
#     CLAWD_DOT_FONT     dots font     CLAWD_DOT_COLOR  dots color (default CLAWD_FG)
#     CLAWD_SESSION_TTL  prune sessions with no update in N seconds (default 28800)
#   Box (bracket) appearance:
#     CLAWD_BG / CLAWD_BORDER / CLAWD_BORDER_WIDTH / CLAWD_RADIUS / CLAWD_HEIGHT
#     CLAWD_FG           foreground/accent color (default near-white)
clawd_load_config() {
  CLAWD_STYLE="${CLAWD_STYLE:-image}"
  CLAWD_POSITION="${CLAWD_POSITION:-right}"

  CLAWD_FG="${CLAWD_FG:-0xfff5f5f7}"

  # sprite (image mode)
  CLAWD_FRAMES_DIR="${CLAWD_FRAMES_DIR:-}"
  CLAWD_IMG_SCALE="${CLAWD_IMG_SCALE:-0.4}"
  CLAWD_IMG_WIDTH="${CLAWD_IMG_WIDTH:-34}"
  CLAWD_IMG_PAD_LEFT="${CLAWD_IMG_PAD_LEFT:-0}"
  CLAWD_SHIPPED_COLOR="ffffff"
  CLAWD_SHIPPED_DEAD="7b7d7b"
  CLAWD_COLOR="${CLAWD_COLOR:-$CLAWD_SHIPPED_COLOR}"
  CLAWD_DEAD_COLOR="${CLAWD_DEAD_COLOR:-$CLAWD_SHIPPED_DEAD}"
  CLAWD_ICON_FONT="${CLAWD_ICON_FONT:-Hack Nerd Font:Bold:12.0}"
  CLAWD_FRAME_MS="${CLAWD_FRAME_MS:-150}"

  # per-session dots
  CLAWD_SHOW_DOTS="${CLAWD_SHOW_DOTS:-1}"
  CLAWD_DOT_IDLE="${CLAWD_DOT_IDLE:-○}"
  CLAWD_DOT_WORK="${CLAWD_DOT_WORK:-●}"
  CLAWD_DOT_WAIT="${CLAWD_DOT_WAIT:-◐}"
  CLAWD_DOT_SEP="${CLAWD_DOT_SEP:- }"
  CLAWD_DOT_FONT="${CLAWD_DOT_FONT:-Hack Nerd Font:Bold:14.0}"   # geometric glyphs render uniform here
  CLAWD_DOT_COLOR="${CLAWD_DOT_COLOR:-$CLAWD_FG}"
  CLAWD_SESSION_TTL="${CLAWD_SESSION_TTL:-28800}"

  # box
  CLAWD_BG="${CLAWD_BG:-0x22ffffff}"
  CLAWD_BORDER="${CLAWD_BORDER:-0x33ffffff}"
  CLAWD_BORDER_WIDTH="${CLAWD_BORDER_WIDTH:-1}"
  CLAWD_RADIUS="${CLAWD_RADIUS:-8}"
  CLAWD_HEIGHT="${CLAWD_HEIGHT:-26}"

  # Mascot frames. CLAWD_WORK is a space-separated frame list (the sprite blinks
  # while any session is working). In image mode frames are PNG paths.
  case "$CLAWD_STYLE" in
    braille)
      CLAWD_IDLE="⡏⣿⣹"; CLAWD_WAIT="⢇⣿⡸"; CLAWD_WORK="⡏⣿⣹ ⢏⣿⡹ ⣾⣿⣷ ⢏⣿⡹" ;;
    ascii)
      CLAWD_IDLE="(o.o)"; CLAWD_WAIT="(o.?)"; CLAWD_WORK="(o.o) (-.o) (o.o) (o.-)" ;;
    blocks)
      CLAWD_IDLE="▖▟██▙▗"; CLAWD_WAIT="▘▟██▙▝"; CLAWD_WORK="▖▟██▙▗ ▌▟██▙▐ ▘▟██▙▝ ▌▟██▙▐" ;;
    image | *)
      CLAWD_STYLE="image"
      _f="${CLAWD_FRAMES_DIR}"
      CLAWD_IDLE="$_f/clawd-open.png"
      CLAWD_WAIT="$_f/clawd-open.png"
      CLAWD_DEAD="$_f/clawd-dead.png"
      CLAWD_WORK="$_f/clawd-open.png $_f/clawd-open.png $_f/clawd-open.png $_f/clawd-open.png $_f/clawd-open.png $_f/clawd-closed.png" ;;
  esac
}
