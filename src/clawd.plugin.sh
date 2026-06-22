#!/bin/sh
# clawd.plugin.sh — SketchyBar item script for the clawd mascot.
#
# SketchyBar runs this on the forced initial load and on every `claude_state`
# event the mascot item subscribes to. It reads $STATE (the event's trigger
# variable), highlights the matching status segment, and starts/stops a small
# background worker that cycles the mascot frames while Claude is working.
#
# A background worker is used (not update_freq) because SketchyBar's polling is
# whole-second; the wiggle needs sub-second frames. The worker is this same
# script re-executed with the `__clawd_anim__` argument, so it shows up as a
# "clawd.plugin.sh __clawd_anim__" process and can always be found and reaped.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=src/clawd.lib.sh
. "$DIR/clawd.lib.sh"
clawd_load_config

# The SketchyBar daemon that spawns this script does NOT inherit the rc's
# exported CLAWD_* vars, so pick up the snapshot clawd.widget.sh persisted.
STATE_DIR="$(clawd_state_dir)"
# shellcheck disable=SC1091
[ -f "$STATE_DIR/clawd.env" ] && . "$STATE_DIR/clawd.env"
clawd_load_config   # re-derive frames for any overridden style
mkdir -p "$STATE_DIR"
PIDFILE="$STATE_DIR/anim.pid"

# Resolve sketchybar regardless of the daemon's (often minimal) PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/usr/bin:/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null)" || exit 0
[ -n "$SB" ] || exit 0

# Frame interval (ms -> fractional seconds for `sleep`).
SLEEP_S="$(awk "BEGIN { printf \"%.3f\", ${CLAWD_FRAME_MS} / 1000 }" 2>/dev/null)"
[ -n "${SLEEP_S:-}" ] || SLEEP_S="0.15"

# --- animation worker --------------------------------------------------------
# Re-entered as `clawd.plugin.sh __clawd_anim__` (backgrounded by the working branch).
if [ "${1:-}" = "__clawd_anim__" ]; then
  while :; do
    for f in $CLAWD_WORK; do
      "$SB" --set clawd icon="$f" >/dev/null 2>&1
      sleep "$SLEEP_S"
    done
  done
  exit 0
fi

ANIM_TAG="clawd.plugin.sh __clawd_anim__"

stop_anim() {
  if [ -f "$PIDFILE" ]; then
    _pid="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "${_pid:-}" ]; then
      kill "$_pid" 2>/dev/null
      pkill -P "$_pid" 2>/dev/null   # reap the in-flight `sleep` child too
    fi
    rm -f "$PIDFILE"
  fi
  # Backstop: reap any stray worker not tracked by the pidfile (e.g. orphaned by
  # a SketchyBar restart). Runs on every state change and on the forced reload
  # run, so the widget self-heals.
  pkill -f "$ANIM_TAG" 2>/dev/null
}

anim_alive() {
  [ -f "$PIDFILE" ] || return 1
  _pid="$(cat "$PIDFILE" 2>/dev/null)"
  [ -n "${_pid:-}" ] && kill -0 "$_pid" 2>/dev/null
}

# Determine the requested state. On the forced/initial/reload run there is no
# claude_state event, so default to idle — which also reaps any orphaned worker.
case "${SENDER:-}" in
  claude_state) ST="${STATE:-idle}" ;;
  *) ST="idle" ;;
esac
case "$ST" in
  working | waiting | idle) ;;
  *) ST="idle" ;;
esac

# Highlight the active status segment (only if segments are drawn).
if [ "${CLAWD_SHOW_LABELS:-1}" = "1" ]; then
  ci="$CLAWD_MUTED"; cw="$CLAWD_MUTED"; ct="$CLAWD_MUTED"
  case "$ST" in
    working) cw="$CLAWD_FG" ;;
    waiting) ct="$CLAWD_FG" ;;
    idle) ci="$CLAWD_FG" ;;
  esac
  "$SB" --set clawd.idle label.color="$ci" \
        --set clawd.work label.color="$cw" \
        --set clawd.wait label.color="$ct" >/dev/null 2>&1
fi

case "$ST" in
  working)
    if ! anim_alive; then        # idempotent: don't restart a live worker
      stop_anim
      # Detach: redirect all fds off SketchyBar's stdout pipe so the pipe closes
      # when this script returns. Otherwise SketchyBar blocks on the inherited
      # pipe and the worker never runs free.
      "$DIR/clawd.plugin.sh" __clawd_anim__ </dev/null >/dev/null 2>&1 &
      echo $! >"$PIDFILE"
    fi
    ;;
  waiting)
    stop_anim
    "$SB" --set clawd icon="$CLAWD_WAIT" >/dev/null 2>&1
    ;;
  *)
    stop_anim
    "$SB" --set clawd icon="$CLAWD_IDLE" >/dev/null 2>&1
    ;;
esac

exit 0
