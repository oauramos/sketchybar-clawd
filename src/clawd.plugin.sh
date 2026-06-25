#!/bin/sh
# clawd.plugin.sh — SketchyBar item script for the clawd Claude Code mascot(s).
#
# Runs on the forced initial load and on every `claude_state` event, reads the
# per-session state store, and renders one of two layouts (CLAWD_MODE):
#   herd  — one clawd PER session, each acting out its own state (hammering,
#           arm-up waving, dead, asleep), capped at CLAWD_HERD_MAX then "+K".
#   hero  — a single mascot reflecting the most-urgent session, plus a glyph
#           strip with one glyph per session, urgency-sorted and capped.
# Either way the box border turns orange while any session is waiting on you.
#
# Smooth motion comes from a background worker (this script re-executed as
# `__clawd_anim__` / `__clawd_herd_anim__`), because SketchyBar's update_freq is
# whole-second — too coarse. The hero worker re-reads anim.state before every
# frame; the herd worker advances every animated slot on a shared tick.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
CLAWD_FRAMES_DIR="$DIR/frames"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=clawd.lib.sh
. "$DIR/clawd.lib.sh"
clawd_load_config

# The daemon that spawns this script doesn't inherit the rc's exported vars.
STATE_DIR="$(clawd_state_dir)"
# shellcheck disable=SC1091
[ -f "$STATE_DIR/clawd.env" ] && . "$STATE_DIR/clawd.env"
clawd_load_config
mkdir -p "$STATE_DIR"
PIDFILE="$STATE_DIR/anim.pid"
ANIM_STATE="$STATE_DIR/anim.state"      # hero worker: line1 interval s, line2 frames
HPIDFILE="$STATE_DIR/herd.pid"
MULTI="$STATE_DIR/multi.state"          # herd worker: "<item> <frame0> <frame1>" per line
BOX="clawd_box"                          # bracket name (see clawd.widget.sh)
SESS="$(clawd_sessions_dir)"; mkdir -p "$SESS"

export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/usr/bin:/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null)" || exit 0
[ -n "$SB" ] || exit 0

ms_to_s() { awk "BEGIN { printf \"%.3f\", ${1:-150} / 1000 }" 2>/dev/null; }
HERD_S="$(ms_to_s "$CLAWD_HERD_MS")"; [ -n "$HERD_S" ] || HERD_S="0.18"

# Call-to-action blink (no sessions): a single neutral-white clawd just blinks —
# eyes open/closed, no hammer, no raised arms, no zzz. Always the SHIPPED white
# frames ("$DIR/frames", never recolored) so it reads as "nobody home — start me"
# regardless of the per-state colors. Mostly-open list = a brief, natural blink.
BLINK_OPEN="$DIR/frames/clawd-open.png"
BLINK_CLOSED="$DIR/frames/clawd-closed.png"
BLINK_FRAMES="$BLINK_OPEN $BLINK_OPEN $BLINK_OPEN $BLINK_OPEN $BLINK_CLOSED"
BLINK_S="$(ms_to_s "$CLAWD_BLINK_MS")"; [ -n "$BLINK_S" ] || BLINK_S="0.2"

# Set an item's image, falling back to the open frame if an image frame is
# missing (a half-deleted recolor cache, etc.) so clawd never vanishes.
img_set() {  # $1 item, $2 frame
  _f="$2"
  if [ "$CLAWD_STYLE" = "image" ] && [ ! -f "$_f" ]; then _f="${CLAWD_F_OPEN:-$_f}"; fi
  if [ "$CLAWD_STYLE" = "image" ]; then "$SB" --set "$1" background.image="$_f" >/dev/null 2>&1
  else "$SB" --set "$1" icon="$_f" >/dev/null 2>&1; fi
}
set_sprite() { img_set clawd "$1"; }     # the hero item is named "clawd"

# --- hero animation worker (re-exec) -----------------------------------------
# Plays anim.state's frame list, re-reading the file before EVERY frame so the
# plugin can switch the hero's pose/interval just by rewriting it (latency ≤ 1
# frame). _idx walks the list, wrapping modulo its current length.
if [ "${1:-}" = "__clawd_anim__" ]; then
  _last=""; _idx=0
  while :; do
    _int=""; _frames=""
    if [ -f "$ANIM_STATE" ]; then
      { IFS= read -r _int; IFS= read -r _frames; } < "$ANIM_STATE" 2>/dev/null
    fi
    [ -n "$_int" ] || _int="0.15"
    [ -n "$_frames" ] || _frames="$CLAWD_IDLE"
    _n=0; for f in $_frames; do _n=$((_n + 1)); done
    [ "$_n" -gt 0 ] || _n=1
    _sel=$((_idx % _n)); _i=0; _pick=""
    for f in $_frames; do [ "$_i" -eq "$_sel" ] && _pick="$f"; _i=$((_i + 1)); done
    [ "$_pick" != "$_last" ] && set_sprite "$_pick"
    _last="$_pick"; _idx=$((_idx + 1))
    sleep "$_int"
  done
  exit 0
fi

# --- herd animation worker (re-exec) -----------------------------------------
# Advances every animated slot's frames on a shared tick, re-reading multi.state
# each tick so added/removed/changed slots are picked up. A line is
# "<item> <frame...>" with any number of frames (≥1); the slot cycles through
# them modulo the count — 2 frames for the hammer/wave, more for the idle blink.
if [ "${1:-}" = "__clawd_herd_anim__" ]; then
  _tick=0
  while :; do
    if [ -f "$MULTI" ]; then
      while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        # shellcheck disable=SC2086
        set -- $_line
        _it="$1"; shift
        { [ -n "$_it" ] && [ "$#" -gt 0 ]; } || continue
        _sel=$((_tick % $#)); _j=0; _fr=""
        for _f in "$@"; do [ "$_j" -eq "$_sel" ] && _fr="$_f"; _j=$((_j + 1)); done
        [ -f "$_fr" ] && "$SB" --set "$_it" background.image="$_fr" >/dev/null 2>&1
      done < "$MULTI"
    fi
    _tick=$((_tick + 1)); sleep "$HERD_S"
  done
  exit 0
fi

# --- worker lifecycle (PID file + command-line guard against PID reuse) -------
_kill_worker() {  # $1 pidfile, $2 tag
  if [ -f "$1" ]; then
    _pid="$(cat "$1" 2>/dev/null)"
    [ -n "${_pid:-}" ] && { kill "$_pid" 2>/dev/null; pkill -P "$_pid" 2>/dev/null; }
    rm -f "$1"
  fi
  pkill -f "$2" 2>/dev/null
}
_worker_alive() {  # $1 pidfile, $2 tag
  [ -f "$1" ] || return 1
  _pid="$(cat "$1" 2>/dev/null)"
  [ -n "${_pid:-}" ] && kill -0 "$_pid" 2>/dev/null || return 1
  ps -o command= -p "$_pid" 2>/dev/null | grep -q "$2"
}
stop_anim()  { _kill_worker "$PIDFILE" "__clawd_anim__"; }
stop_herd()  { _kill_worker "$HPIDFILE" "__clawd_herd_anim__"; }
anim_alive() { _worker_alive "$PIDFILE" "__clawd_anim__"; }
herd_alive() { _worker_alive "$HPIDFILE" "__clawd_herd_anim__"; }
start_anim() {
  anim_alive && return 0
  stop_anim
  "$DIR/clawd.plugin.sh" __clawd_anim__ </dev/null >/dev/null 2>&1 &
  echo $! >"$PIDFILE"
}
start_herd() {
  herd_alive && return 0
  stop_herd
  "$DIR/clawd.plugin.sh" __clawd_herd_anim__ </dev/null >/dev/null 2>&1 &
  echo $! >"$HPIDFILE"
}

set_border() {  # orange while $1 == waiting, else normal
  if [ "$1" = "waiting" ]; then _bc="$CLAWD_BORDER_WAIT"; else _bc="$CLAWD_BORDER"; fi
  "$SB" --set "$BOX" background.border_color="$_bc" >/dev/null 2>&1
}

# Overlay the "?" badge label on a waiting item, clear it otherwise. Font/color/
# position are baked in at item creation (clawd.widget.sh); we only toggle text.
set_ask() {  # $1 item, $2 state
  if [ "$2" = "waiting" ]; then
    "$SB" --set "$1" label="$CLAWD_ASK_GLYPH" label.drawing=on >/dev/null 2>&1
  else
    "$SB" --set "$1" label.drawing=off >/dev/null 2>&1
  fi
}

# per-state frames for a herd slot: animated states echo "f0 f1", else empty
herd_frames() {
  case "$1" in
    working) printf '%s %s' "$CLAWD_F_HUP" "$CLAWD_F_HDOWN" ;;
  esac
}
herd_static() {
  case "$1" in
    error)   printf '%s' "$CLAWD_F_DEAD" ;;
    waiting) printf '%s' "$CLAWD_F_WAIT" ;;   # alert open body; "?" badge added separately
    *)       printf '%s' "$CLAWD_F_SLEEP" ;;
  esac
}

now="$(date +%s)"

# =============================================================================
# HERO: one mascot for the most-urgent session + a glyph strip
# =============================================================================
hero_main() {
  stop_herd
  n_wait=0; n_err=0; n_work=0; n_idle=0; total=0
  for f in "$SESS"/*; do
    [ -f "$f" ] || continue
    mt="$(stat -f %m "$f" 2>/dev/null || echo "$now")"
    if [ $((now - mt)) -gt "$CLAWD_SESSION_TTL" ]; then rm -f "$f"; continue; fi
    case "$(cat "$f" 2>/dev/null)" in
      waiting) n_wait=$((n_wait + 1)) ;;
      error)   n_err=$((n_err + 1)) ;;
      working) n_work=$((n_work + 1)) ;;
      *)       n_idle=$((n_idle + 1)) ;;
    esac
    total=$((total + 1))
  done

  # No sessions at all (image mode): a single neutral-white clawd just blinks as
  # a "start me" call to action — no sleep pose, no props, no status strip.
  if [ "$total" -eq 0 ] && [ "$CLAWD_STYLE" = "image" ]; then
    [ "${CLAWD_SHOW_DOTS:-1}" = "1" ] && "$SB" --set clawd.sessions label="" label.drawing=off >/dev/null 2>&1
    set_border "ok"; set_ask clawd "ok"
    if printf '%s\n%s\n' "$BLINK_S" "$BLINK_FRAMES" >"$ANIM_STATE.tmp" 2>/dev/null \
       && mv "$ANIM_STATE.tmp" "$ANIM_STATE" 2>/dev/null; then
      start_anim
    else
      stop_anim; img_set clawd "$BLINK_OPEN"
    fi
    return 0
  fi

  if   [ "$n_wait" -gt 0 ]; then top="waiting"
  elif [ "$n_err"  -gt 0 ]; then top="error"
  elif [ "$n_work" -gt 0 ]; then top="working"
  else                          top="idle"
  fi

  # strip: urgency-sorted glyphs, capped at CLAWD_STRIP_MAX, then +K
  STRIP_OUT=""; STRIP_SHOWN=0
  strip_add() {  # $1 glyph, $2 count
    _g="$1"; _c="$2"
    while [ "$_c" -gt 0 ]; do
      [ "$STRIP_SHOWN" -ge "$CLAWD_STRIP_MAX" ] && return 0
      if [ -z "$STRIP_OUT" ]; then STRIP_OUT="$_g"; else STRIP_OUT="$STRIP_OUT$CLAWD_DOT_SEP$_g"; fi
      STRIP_SHOWN=$((STRIP_SHOWN + 1)); _c=$((_c - 1))
    done
  }
  strip_add "$CLAWD_DOT_WAIT" "$n_wait"
  strip_add "$CLAWD_DOT_ERR"  "$n_err"
  strip_add "$CLAWD_DOT_WORK" "$n_work"
  strip_add "$CLAWD_DOT_IDLE" "$n_idle"
  _hidden=$((total - STRIP_SHOWN))
  [ "$_hidden" -gt 0 ] && STRIP_OUT="$STRIP_OUT$CLAWD_DOT_SEP+$_hidden"
  if [ "${CLAWD_SHOW_DOTS:-1}" = "1" ]; then
    "$SB" --set clawd.sessions label="$STRIP_OUT" label.drawing=on >/dev/null 2>&1
  fi

  set_border "$top"; set_ask clawd "$top"

  anim="$(clawd_anim "$top")"           # "<interval_ms> <frame...>"
  int_ms="${anim%% *}"; frames="${anim#* }"
  if [ "$int_ms" = "0" ]; then          # static pose — no worker needed
    stop_anim
    img_set clawd "$frames"
  elif printf '%s\n%s\n' "$(ms_to_s "$int_ms")" "$frames" >"$ANIM_STATE.tmp" 2>/dev/null \
       && mv "$ANIM_STATE.tmp" "$ANIM_STATE" 2>/dev/null; then
    start_anim                          # animated pose — frames persisted, ensure worker
  else
    stop_anim                           # couldn't persist frames — show the first statically
    img_set clawd "${frames%% *}"
  fi
}

# =============================================================================
# HERD: one clawd per session (sorted by start time), capped then "+K"
# =============================================================================
herd_main() {
  stop_anim
  # sessions sorted by birth time (stable left->right order), pruning stale ones
  _list="$(for f in "$SESS"/*; do
    [ -f "$f" ] || continue
    mt="$(stat -f %m "$f" 2>/dev/null || echo "$now")"
    [ $((now - mt)) -gt "$CLAWD_SESSION_TTL" ] && { rm -f "$f"; continue; }
    printf '%s %s\n' "$(stat -f %B "$f" 2>/dev/null || echo 0)" "$f"
  done | sort -n | awk '{ print $2 }')"
  _count=0; for f in $_list; do _count=$((_count + 1)); done
  _shown="$_count"; [ "$_shown" -gt "$CLAWD_HERD_MAX" ] && _shown="$CLAWD_HERD_MAX"

  # Border alarm scans EVERY session, not just the visible ones — a waiting
  # session folded into the "+K" overflow must still glow the box orange.
  _anywait=0
  for f in $_list; do [ "$(cat "$f" 2>/dev/null)" = "waiting" ] && { _anywait=1; break; }; done

  # Pass 1: build the animated-slot manifest and publish it BEFORE setting any
  # slot image, so the worker stops touching a slot the instant it goes static
  # (otherwise a stale in-flight frame could clobber the static pose).
  : >"$MULTI.tmp"
  _i=0
  for f in $_list; do
    [ "$_i" -ge "$_shown" ] && break
    _hf="$(herd_frames "$(cat "$f" 2>/dev/null)")"
    [ -n "$_hf" ] && printf 'clawd.s%s %s\n' "$_i" "$_hf" >>"$MULTI.tmp"
    _i=$((_i + 1))
  done
  # No sessions: slot 0 becomes a blinking white call-to-action (open/closed eyes).
  [ "$_count" -eq 0 ] && printf 'clawd.s0 %s\n' "$BLINK_FRAMES" >>"$MULTI.tmp"
  mv "$MULTI.tmp" "$MULTI" 2>/dev/null

  # Pass 2: set each visible slot's pose + show it.
  _i=0
  for f in $_list; do
    [ "$_i" -ge "$_shown" ] && break
    _st="$(cat "$f" 2>/dev/null)"; _hf="$(herd_frames "$_st")"
    if [ -n "$_hf" ]; then img_set "clawd.s$_i" "${_hf%% *}"
    else img_set "clawd.s$_i" "$(herd_static "$_st")"; fi
    set_ask "clawd.s$_i" "$_st"
    "$SB" --set "clawd.s$_i" drawing=on >/dev/null 2>&1
    _i=$((_i + 1))
  done
  # no sessions at all -> one white clawd blinking (call to action) — the worker
  # cycles its frames (manifest written above); seed the open frame + show it.
  if [ "$_count" -eq 0 ]; then
    img_set clawd.s0 "$BLINK_OPEN"; set_ask clawd.s0 "ok"
    "$SB" --set clawd.s0 drawing=on >/dev/null 2>&1; _i=1
  fi
  while [ "$_i" -lt "$CLAWD_HERD_MAX" ]; do "$SB" --set "clawd.s$_i" drawing=off >/dev/null 2>&1; _i=$((_i + 1)); done

  _over=$((_count - _shown))
  if [ "$_over" -gt 0 ]; then "$SB" --set clawd.more label="+$_over" label.drawing=on drawing=on >/dev/null 2>&1
  else "$SB" --set clawd.more drawing=off >/dev/null 2>&1; fi

  if [ "$_anywait" = "1" ]; then set_border "waiting"; else set_border "ok"; fi

  if [ -s "$MULTI" ]; then start_herd; else stop_herd; fi
}

# --- dispatch ----------------------------------------------------------------
if [ "$CLAWD_MODE" = "herd" ] && [ "$CLAWD_STYLE" = "image" ]; then
  herd_main
else
  hero_main
fi
exit 0
