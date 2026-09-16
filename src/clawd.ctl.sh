#!/bin/sh
# clawd.ctl.sh — the `sketchybar-clawd` command: change how many sessions the bar
# shows before folding the rest into "+K", from the terminal, without editing
# sketchybarrc.
#
#   sketchybar-clawd            what the bar is showing right now
#   sketchybar-clawd 12         show up to 12 sessions, then "+K"   (also: max 12)
#   sketchybar-clawd reset      back to the rc's CLAWD_HERD_MAX / CLAWD_STRIP_MAX
#
# The number is written to the state dir (clawd_cap_file); the widget and the
# plugin both read it, so it outlives `sketchybar --reload`. Herd slots are bar
# items only the widget can add, so a number above the pool it built
# (CLAWD_HERD_POOL) costs one reload — done here, and the pool grows to fit. In
# hero mode there is no pool: the dot strip just changes length.
set -u

# Find the widget dir through however many symlinks lead here (the installer
# links this file onto PATH; a --link install adds one more hop).
_self="$0"
while [ -L "$_self" ]; do
  _t="$(readlink "$_self")"
  case "$_t" in /*) _self="$_t" ;; *) _self="$(dirname "$_self")/$_t" ;; esac
done
DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd)"
[ -f "$DIR/clawd.lib.sh" ] || DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar}/clawd"
if [ ! -f "$DIR/clawd.lib.sh" ]; then
  echo "sketchybar-clawd: clawd.lib.sh not found (looked in $DIR) — is the widget installed?" >&2
  exit 1
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=clawd.lib.sh
. "$DIR/clawd.lib.sh"
clawd_load_config
STATE_DIR="$(clawd_state_dir)"
ENV_FILE="$STATE_DIR/clawd.env"      # the rc's resolved settings, written by the widget
# shellcheck disable=SC1090,SC1091
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
clawd_load_config
CAP_FILE="$(clawd_cap_file)"

export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/usr/bin:/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null || true)"

usage() {
  cat <<'EOF'
usage: sketchybar-clawd [N | reset | status]

  sketchybar-clawd          what the bar is showing right now
  sketchybar-clawd 12       show up to 12 sessions, then "+K"   (also: max 12)
  sketchybar-clawd reset    back to the rc's CLAWD_HERD_MAX / CLAWD_STRIP_MAX
EOF
}
die() { echo "sketchybar-clawd: $*" >&2; exit 1; }

# herd = one slot item per clawd, bounded by the pool; hero = a text strip, unbounded
herd() { [ "$CLAWD_MODE" = "herd" ] && [ "$CLAWD_STYLE" = "image" ]; }

# Slots the running bar actually has. Only the widget writes this line, so a
# clawd.env without it (never loaded, or older than this command) means the bar
# needs a reload before any cap above the rc value can be drawn.
bar_pool() { sed -n 's/^CLAWD_HERD_POOL=//p' "$ENV_FILE" 2>/dev/null; }

sessions() {
  _n=0
  for _f in "$(clawd_sessions_dir)"/*; do [ -f "$_f" ] && _n=$((_n + 1)); done
  printf '%s' "$_n"
}

# Redraw the bar. Nothing to poke without sketchybar — the cap file still
# applies the next time the widget loads.
redraw() {
  [ -n "$SB" ] || { echo "  (sketchybar not on PATH — takes effect on the next reload)"; return 0; }
  "$SB" --trigger claude_state
}

status() {
  _ov="$(clawd_cap_override)"
  if herd; then _cap="$CLAWD_HERD_MAX"; _what="clawds"; else _cap="$CLAWD_STRIP_MAX"; _what="dots"; fi
  if [ -n "$_ov" ]; then _src="set by sketchybar-clawd; rc says $_cap"; _cap="$_ov"
  else _src="the rc default"; fi
  _n="$(sessions)"; _over=$((_n - _cap))
  echo "cap:      up to $_cap $_what, then +K   ($_src)"
  if [ "$_over" -gt 0 ]; then echo "sessions: $_n  (+$_over folded)"; else echo "sessions: $_n"; fi
  if herd; then
    _pool="$(bar_pool)"
    if [ -n "$_pool" ]; then echo "pool:     $_pool slots — a cap above this reloads SketchyBar"
    else echo "pool:     unknown — the bar hasn't loaded this version of the widget yet"; fi
  fi
}

set_cap() {  # $1 = N
  case "${1:-}" in "" | *[!0-9]*) die "expected a number, got '${1:-}' (try: sketchybar-clawd 12)" ;; esac
  [ "$1" -ge 1 ] || die "the cap must be at least 1 — 'sketchybar-clawd reset' restores the rc default"
  mkdir -p "$STATE_DIR" 2>/dev/null
  { printf '%s\n' "$1" >"$CAP_FILE.tmp" && mv "$CAP_FILE.tmp" "$CAP_FILE"; } 2>/dev/null \
    || die "cannot write $CAP_FILE"
  if herd; then
    _pool="$(bar_pool)"
    if [ -z "$_pool" ] || [ "$1" -gt "$_pool" ]; then
      [ -n "$SB" ] || { echo "up to $1 clawds, then +K  (sketchybar not on PATH — takes effect on the next reload)"; return 0; }
      echo "up to $1 clawds, then +K — growing the slot pool${_pool:+ from $_pool}, reloading SketchyBar"
      "$SB" --reload; return $?          # the widget re-reads the cap and sizes the pool to it
    fi
    echo "up to $1 clawds, then +K"
  else
    echo "up to $1 dots, then +K"
  fi
  redraw
}

reset_cap() {
  rm -f "$CAP_FILE" "$CAP_FILE.tmp" 2>/dev/null
  if herd; then echo "back to the rc default: up to $CLAWD_HERD_MAX clawds, then +K"
  else echo "back to the rc default: up to $CLAWD_STRIP_MAX dots, then +K"; fi
  redraw
}

case "${1:-}" in
  "" | status) status ;;
  reset | default) reset_cap ;;
  max) set_cap "${2:-}" ;;
  max=*) set_cap "${1#max=}" ;;
  -h | --help | help) usage ;;
  *) set_cap "$1" ;;
esac
