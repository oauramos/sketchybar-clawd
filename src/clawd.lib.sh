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

# Map a session state to its status-strip glyph.
clawd_dot() {
  case "$1" in
    working) printf '%s' "$CLAWD_DOT_WORK" ;;
    waiting) printf '%s' "$CLAWD_DOT_WAIT" ;;
    error) printf '%s' "$CLAWD_DOT_ERR" ;;
    *) printf '%s' "$CLAWD_DOT_IDLE" ;;
  esac
}

# Urgency rank (higher = more urgent). The most-urgent session drives the hero
# mascot, and the status strip is sorted by it: waiting > error > working > idle.
clawd_priority() {
  case "$1" in
    waiting) printf 4 ;;
    error) printf 3 ;;
    working) printf 2 ;;
    idle) printf 1 ;;
    *) printf 0 ;;
  esac
}

# Echo "<interval_ms> <frame...>" — the hero mascot animation for a state.
# interval_ms 0 = a single static frame (no animation worker needed).
clawd_anim() {
  case "$1" in
    working) printf '%s' "$CLAWD_ANIM_WORK" ;;
    waiting) printf '%s' "$CLAWD_ANIM_WAIT" ;;
    error) printf '%s' "$CLAWD_ANIM_ERROR" ;;
    *) printf '%s' "$CLAWD_ANIM_IDLE" ;;
  esac
}

# Resolve every CLAWD_* setting from the environment, applying defaults, and
# select the mascot frames. Idempotent — safe to call again after sourcing an
# overrides file.
#
# Knobs (override via environment before sourcing clawd.widget.sh):
#   Multi-session display:
#     CLAWD_MODE         herd (default, one clawd per session) | hero (one most-urgent
#                        mascot + a glyph strip). herd needs CLAWD_STYLE=image.
#     CLAWD_HERD_MAX     clawds shown before collapsing to "+K" (default 6)
#     CLAWD_HERD_MS      herd animation frame interval ms (default 180)
#   Mascot (the clawd sprite):
#     CLAWD_STYLE        image (default, pixel-art sprite) | blocks | braille | ascii
#     CLAWD_POSITION     right (default) | left | center
#     CLAWD_IMG_SCALE    sprite scale (default 0.4)        CLAWD_IMG_WIDTH  px (default 34)
#     CLAWD_IMG_PAD_LEFT left margin before the sprite, px (default 0)
#     CLAWD_COLOR        sprite color RRGGBB (default neutral white; auto-recolors
#                        via the bundled generator — needs python3 — and caches it)
#     CLAWD_COLOR_WORK / CLAWD_COLOR_IDLE / CLAWD_COLOR_WAIT   per-state sprite colors
#                        (each defaults to CLAWD_COLOR; e.g. orange working, gray idle)
#     CLAWD_DEAD_COLOR   "dead"/error sprite color (default 7b7d7b)
#     CLAWD_FRAME_MS     working (hammer) frame interval ms (default 150)
#     CLAWD_BLINK_MS     no-session blink frame interval ms (default 200). With no
#                        sessions a single neutral-white clawd just blinks (eyes
#                        open/closed, no props) as a "start me" call to action.
#     CLAWD_ICON_FONT    mascot font (glyph styles only)
#   Waiting "?" badge (a session is waiting on you -> a "?" over its top-right):
#     CLAWD_ASK_GLYPH    badge text (default "?")
#     CLAWD_ASK_COLOR    badge color (default CLAWD_FG / near-white)
#     CLAWD_ASK_FONT     badge font   (default small bold)
#     CLAWD_ASK_YOFF     badge vertical nudge, +up (default 5)
#   Per-session status strip (one glyph per running Claude Code session):
#     CLAWD_SHOW_DOTS    1 (default) | 0 (mascot only)
#     CLAWD_DOT_IDLE / CLAWD_DOT_WORK / CLAWD_DOT_WAIT / CLAWD_DOT_ERR  glyphs (○ ● ◐ ✗)
#     CLAWD_DOT_SEP      separator between glyphs (default " ")
#     CLAWD_DOT_FONT     strip font     CLAWD_DOT_COLOR  strip color (default CLAWD_FG)
#     CLAWD_STRIP_MAX    show at most N glyphs, then "+K" (default 8)
#     CLAWD_SESSION_TTL  prune sessions with no update in N seconds (default 28800)
#   Box (bracket) appearance:
#     CLAWD_BG / CLAWD_BORDER / CLAWD_BORDER_WIDTH / CLAWD_RADIUS / CLAWD_HEIGHT
#     CLAWD_BORDER_WAIT  border color while a session is waiting (default Claude orange)
#     CLAWD_FG           foreground/accent color (default near-white)
clawd_load_config() {
  CLAWD_STYLE="${CLAWD_STYLE:-image}"
  CLAWD_POSITION="${CLAWD_POSITION:-right}"
  # Multi-session display: herd = one clawd per session (default); hero = a single
  # most-urgent mascot + a glyph strip. (herd needs image style; else falls back.)
  CLAWD_MODE="${CLAWD_MODE:-herd}"
  CLAWD_HERD_MAX="${CLAWD_HERD_MAX:-6}"   # clawds shown before collapsing to "+K"
  CLAWD_HERD_MS="${CLAWD_HERD_MS:-180}"   # herd animation frame interval (ms)

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
  # Per-state sprite colors (default to CLAWD_COLOR = monochrome). The widget
  # generates one recolored frame set per distinct color.
  CLAWD_COLOR_WORK="${CLAWD_COLOR_WORK:-$CLAWD_COLOR}"
  CLAWD_COLOR_IDLE="${CLAWD_COLOR_IDLE:-$CLAWD_COLOR}"
  CLAWD_COLOR_WAIT="${CLAWD_COLOR_WAIT:-$CLAWD_COLOR}"
  CLAWD_ART_VER="5"   # bump when gen-clawd.py art changes, to bust recolor caches
  CLAWD_ICON_FONT="${CLAWD_ICON_FONT:-Hack Nerd Font:Bold:12.0}"
  CLAWD_FRAME_MS="${CLAWD_FRAME_MS:-150}"
  CLAWD_BLINK_MS="${CLAWD_BLINK_MS:-200}"   # no-session "call to action" blink frame interval (ms)

  # Waiting "?" badge (overlaid as the mascot/slot label on a waiting session).
  CLAWD_ASK_GLYPH="${CLAWD_ASK_GLYPH:-?}"
  CLAWD_ASK_COLOR="${CLAWD_ASK_COLOR:-$CLAWD_FG}"    # near-white, matches the mascot
  CLAWD_ASK_FONT="${CLAWD_ASK_FONT:-Hack Nerd Font:Bold:9.0}"
  CLAWD_ASK_YOFF="${CLAWD_ASK_YOFF:-5}"             # +up; small gap below the top border

  # per-session status strip
  CLAWD_SHOW_DOTS="${CLAWD_SHOW_DOTS:-1}"
  CLAWD_DOT_IDLE="${CLAWD_DOT_IDLE:-○}"
  CLAWD_DOT_WORK="${CLAWD_DOT_WORK:-●}"
  CLAWD_DOT_WAIT="${CLAWD_DOT_WAIT:-◐}"
  CLAWD_DOT_ERR="${CLAWD_DOT_ERR:-✗}"
  CLAWD_DOT_SEP="${CLAWD_DOT_SEP:- }"
  CLAWD_DOT_FONT="${CLAWD_DOT_FONT:-Hack Nerd Font:Bold:14.0}"   # geometric glyphs render uniform here
  CLAWD_DOT_COLOR="${CLAWD_DOT_COLOR:-$CLAWD_FG}"
  CLAWD_STRIP_MAX="${CLAWD_STRIP_MAX:-8}"
  CLAWD_SESSION_TTL="${CLAWD_SESSION_TTL:-28800}"

  # box
  CLAWD_BG="${CLAWD_BG:-0x22ffffff}"
  CLAWD_BORDER="${CLAWD_BORDER:-0x33ffffff}"
  CLAWD_BORDER_WAIT="${CLAWD_BORDER_WAIT:-0xffd97757}"   # Claude orange = "come back to me"
  CLAWD_BORDER_WIDTH="${CLAWD_BORDER_WIDTH:-1}"
  CLAWD_RADIUS="${CLAWD_RADIUS:-8}"
  CLAWD_HEIGHT="${CLAWD_HEIGHT:-26}"

  # Mascot frames per pose. In image mode frames are PNG paths; in glyph modes
  # CLAWD_WORK is a space-separated multi-glyph animation, the rest single glyphs.
  case "$CLAWD_STYLE" in
    braille)
      CLAWD_IDLE="⡏⣿⣹"; CLAWD_WAIT="⢇⣿⡸"; CLAWD_DEAD="⡏⣿⣹"
      CLAWD_WORK="⡏⣿⣹ ⢏⣿⡹ ⣾⣿⣷ ⢏⣿⡹" ;;
    ascii)
      CLAWD_IDLE="(-.-)"; CLAWD_WAIT="(o.?)"; CLAWD_DEAD="(x.x)"
      CLAWD_WORK="(o.o) (-.o) (o.o) (o.-)" ;;
    blocks)
      CLAWD_IDLE="▖▟██▙▗"; CLAWD_WAIT="▘▟██▙▝"; CLAWD_DEAD="▖▟⊗⊗▙▗"
      CLAWD_WORK="▖▟██▙▗ ▌▟██▙▐ ▘▟██▙▝ ▌▟██▙▐" ;;
    image | *)
      CLAWD_STYLE="image"
      # Each state pulls frames from its own color dir (set by the widget per
      # CLAWD_COLOR_WORK/IDLE/WAIT); all fall back to the single CLAWD_FRAMES_DIR.
      _f="${CLAWD_FRAMES_DIR}"
      _wd="${CLAWD_DIR_WORK:-$_f}"; _id="${CLAWD_DIR_IDLE:-$_f}"; _td="${CLAWD_DIR_WAIT:-$_f}"
      CLAWD_F_OPEN="$_td/clawd-open.png";   CLAWD_F_CLOSED="$_wd/clawd-closed.png"
      CLAWD_F_DEAD="$_id/clawd-dead.png";   CLAWD_F_SLEEP="$_id/clawd-sleep.png"
      CLAWD_F_HUP="$_wd/clawd-hammer-up.png"; CLAWD_F_HDOWN="$_wd/clawd-hammer-down.png"
      CLAWD_F_WAIT="$_td/clawd-wait.png"
      CLAWD_IDLE="$CLAWD_F_SLEEP"          # idle hero = curled asleep
      CLAWD_WAIT="$CLAWD_F_WAIT"; CLAWD_DEAD="$CLAWD_F_DEAD"
      CLAWD_WORK="$CLAWD_F_HUP $CLAWD_F_HDOWN" ;;
  esac

  # Per-state hero animation strings: "<interval_ms> <frame...>".
  if [ "$CLAWD_STYLE" = "image" ]; then
    CLAWD_ANIM_IDLE="0 $CLAWD_F_SLEEP"
    CLAWD_ANIM_WORK="$CLAWD_FRAME_MS $CLAWD_F_HUP $CLAWD_F_HDOWN"
    CLAWD_ANIM_WAIT="0 $CLAWD_F_WAIT"
    CLAWD_ANIM_ERROR="0 $CLAWD_F_DEAD"
  else
    CLAWD_ANIM_IDLE="0 $CLAWD_IDLE"
    CLAWD_ANIM_WORK="$CLAWD_FRAME_MS $CLAWD_WORK"
    CLAWD_ANIM_WAIT="0 $CLAWD_WAIT"
    CLAWD_ANIM_ERROR="0 $CLAWD_DEAD"
  fi
}
