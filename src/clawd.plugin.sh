#!/bin/sh
# clawd.plugin.sh — SketchyBar item script for the clawd mascot + per-session dots.
#
# Runs on the forced initial load and on every `claude_state` event. It reads the
# per-session state store, renders one dot per session (○ idle, ● working,
# ◐ waiting), and blinks the clawd sprite whenever any session is working.
#
# A background worker (this script re-executed as `__clawd_anim__`) does the blink,
# because SketchyBar's update_freq is whole-second — too coarse for a smooth blink.
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
SESS="$(clawd_sessions_dir)"; mkdir -p "$SESS"

export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/usr/bin:/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null)" || exit 0
[ -n "$SB" ] || exit 0

set_sprite() {
  if [ "$CLAWD_STYLE" = "image" ]; then "$SB" --set clawd background.image="$1" >/dev/null 2>&1
  else "$SB" --set clawd icon="$1" >/dev/null 2>&1; fi
}

SLEEP_S="$(awk "BEGIN { printf \"%.3f\", ${CLAWD_FRAME_MS} / 1000 }" 2>/dev/null)"
[ -n "${SLEEP_S:-}" ] || SLEEP_S="0.15"

# --- blink worker (re-exec) --------------------------------------------------
if [ "${1:-}" = "__clawd_anim__" ]; then
  _last=""
  while :; do
    for f in $CLAWD_WORK; do
      [ "$f" != "$_last" ] && set_sprite "$f"
      _last="$f"; sleep "$SLEEP_S"
    done
  done
  exit 0
fi

ANIM_TAG="clawd.plugin.sh __clawd_anim__"
stop_anim() {
  if [ -f "$PIDFILE" ]; then
    _pid="$(cat "$PIDFILE" 2>/dev/null)"
    [ -n "${_pid:-}" ] && { kill "$_pid" 2>/dev/null; pkill -P "$_pid" 2>/dev/null; }
    rm -f "$PIDFILE"
  fi
  pkill -f "$ANIM_TAG" 2>/dev/null
}
anim_alive() {
  [ -f "$PIDFILE" ] || return 1
  _pid="$(cat "$PIDFILE" 2>/dev/null)"; [ -n "${_pid:-}" ] && kill -0 "$_pid" 2>/dev/null
}

# --- read sessions: build the dot string, detect any-working -----------------
now="$(date +%s)"
dots=""; any_work=0
for f in "$SESS"/*; do
  [ -f "$f" ] || continue
  mt="$(stat -f %m "$f" 2>/dev/null || echo "$now")"
  if [ $((now - mt)) -gt "$CLAWD_SESSION_TTL" ]; then rm -f "$f"; continue; fi
  st="$(cat "$f" 2>/dev/null)"
  [ "$st" = "working" ] && any_work=1
  g="$(clawd_dot "$st")"
  if [ -z "$dots" ]; then dots="$g"; else dots="$dots$CLAWD_DOT_SEP$g"; fi
done

# --- render dots -------------------------------------------------------------
if [ "${CLAWD_SHOW_DOTS:-1}" = "1" ]; then
  "$SB" --set clawd.sessions label="$dots" label.drawing=on >/dev/null 2>&1
fi

# --- sprite: blink while any session works, else rest ------------------------
if [ "$any_work" = "1" ]; then
  if ! anim_alive; then
    stop_anim
    "$DIR/clawd.plugin.sh" __clawd_anim__ </dev/null >/dev/null 2>&1 &
    echo $! >"$PIDFILE"
  fi
else
  stop_anim
  set_sprite "$CLAWD_IDLE"
fi

exit 0
