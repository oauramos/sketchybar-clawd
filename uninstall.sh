#!/usr/bin/env bash
# uninstall.sh — remove the clawd SketchyBar widget.
#
# Removes the installed widget files, the source line from sketchybarrc (if
# writable; backed up first), and the Claude Code hooks. Backups are kept.
#
# Usage:
#   ./uninstall.sh [--config-dir DIR] [--yes] [--keep-hooks]
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar}"
ASSUME_YES=0
KEEP_HOOKS=0

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) CONFIG_DIR="${2:?--config-dir needs a path}"; shift 2 ;;
    -y | --yes) ASSUME_YES=1; shift ;;
    --keep-hooks) KEEP_HOOKS=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "uninstall.sh: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

DEST="$CONFIG_DIR/clawd"
RC="$CONFIG_DIR/sketchybarrc"

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

# Stop any running animation daemon and remove the bar items.
if [ -n "$SB" ]; then
  for it in clawd clawd.idle clawd.work clawd.wait clawd.s1 clawd.s2 clawd_box; do
    "$SB" --remove "$it" >/dev/null 2>&1 || true
  done
fi
PIDFILE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar-clawd/anim.pid"
[ -f "$PIDFILE" ] && { kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; }
pkill -f "clawd.plugin.sh __clawd_anim__" 2>/dev/null || true

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
