#!/usr/bin/env bash
# uninstall.sh — remove the clawd SketchyBar widget.
#
# Removes the installed widget files, the `sketchybar-clawd` command link, the
# source line from sketchybarrc (if writable; backed up first), and the Claude
# Code hooks. Backups are kept.
#
# Usage:
#   ./uninstall.sh [--config-dir DIR] [--bin-dir DIR] [--yes] [--keep-hooks]
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
ASSUME_YES=0
KEEP_HOOKS=0

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) CONFIG_DIR="${2:?--config-dir needs a path}"; shift 2 ;;
    --bin-dir) BIN_DIR="${2:?--bin-dir needs a path}"; shift 2 ;;
    -y | --yes) ASSUME_YES=1; shift ;;
    --keep-hooks) KEEP_HOOKS=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "uninstall.sh: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

DEST="$CONFIG_DIR/clawd"
RC="$CONFIG_DIR/sketchybarrc"
CMD="$BIN_DIR/sketchybar-clawd"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar-clawd"

say()  { printf '%s\n' "$*"; }
step() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  [ -r /dev/tty ] || return 1
  printf '%s [y/N] ' "$1" >/dev/tty
  local ans; read -r ans </dev/tty || return 1
  case "$ans" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

confirm "Remove clawd from $CONFIG_DIR?" || { say "Aborted."; exit 0; }

export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null || true)"

# Stop any running animation workers and remove the bar items (every herd slot
# the widget built — the pool size is in the env it persisted — plus the hero
# items and the box).
if [ -n "$SB" ]; then
  pool="$(sed -n 's/^CLAWD_HERD_POOL=//p' "$CACHE/clawd.env" 2>/dev/null)"
  case "$pool" in "" | *[!0-9]*) pool=24 ;; esac
  for it in clawd clawd.sessions clawd.more $(seq -f 'clawd.s%g' 0 $((pool - 1))) clawd_box; do
    "$SB" --remove "$it" >/dev/null 2>&1 || true
  done
fi
for pf in "$CACHE/anim.pid" "$CACHE/herd.pid"; do
  [ -f "$pf" ] && { kill "$(cat "$pf")" 2>/dev/null || true; rm -f "$pf"; }
done
pkill -f "clawd.plugin.sh __clawd_" 2>/dev/null || true

step "sketchybar-clawd command"
if [ -L "$CMD" ] && [[ "$(readlink "$CMD")" == "$DEST/"* ]]; then
  rm -f "$CMD" && say "  removed $CMD"
elif [ -e "$CMD" ]; then
  warn "$CMD is not our symlink — leaving it alone."
else
  say "  no command link found."
fi

step "Removing widget files"
rm -rf "$DEST" && say "  removed $DEST"

step "sketchybarrc"
if grep -qs 'clawd/clawd.widget.sh' "$RC" 2>/dev/null; then
  if [ -w "$RC" ]; then
    cp "$RC" "$RC.clawd-bak.$(date +%s).$$"
    # drop the source line and the comment line we added above it
    grep -v 'clawd/clawd.widget.sh' "$RC" | grep -v '^# clawd — Claude Code state mascot' >"$RC.tmp" && mv "$RC.tmp" "$RC"
    say "  removed source line (backup written)."
  else
    warn "$RC is not writable — remove the clawd 'source' line yourself."
  fi
else
  say "  no source line found."
fi

step "Claude Code hooks"
if [ "$KEEP_HOOKS" = "1" ]; then
  say "  kept (--keep-hooks)."
elif command -v jq >/dev/null 2>&1; then
  bash "$SELF/hooks/install-hooks.sh" --remove || warn "could not update settings.json"
else
  warn "jq not found — remove the clawd hooks from ~/.claude/settings.json manually."
fi

[ -n "$SB" ] && "$SB" --reload >/dev/null 2>&1 || true
say ""
step "Done."
