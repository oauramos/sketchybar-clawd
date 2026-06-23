#!/usr/bin/env bash
# install-hooks.sh — merge (or remove) the clawd Claude Code hooks in a
# settings.json, using jq. Idempotent and non-destructive: existing keys and
# non-clawd hooks are preserved, a timestamped backup is written before any
# change, and re-running never duplicates entries.
#
# Usage:
#   install-hooks.sh [--hook PATH] [--settings FILE | --project] [--remove] [--dry-run]
#
#   --hook PATH     Path to clawd.hook.sh (default: $CONFIG_DIR/clawd/clawd.hook.sh
#                   or ~/.config/sketchybar/clawd/clawd.hook.sh)
#   --settings FILE Target settings file (default: ~/.claude/settings.json)
#   --project       Target ./.claude/settings.json in the current directory
#   --remove        Remove the clawd hooks instead of adding them
#   --dry-run       Print the resulting JSON, write nothing
set -euo pipefail

# This writes a user-owned Claude Code settings.json (default ~/.claude). Running
# under sudo would create root-owned files that lock the real user out, so refuse.
if [ "$(id -u)" -eq 0 ]; then
  echo "install-hooks.sh: refusing to run as root — it edits a user's .claude/settings.json; run as your normal user (no sudo)." >&2
  exit 1
fi

SETTINGS="${HOME}/.claude/settings.json"
HOOK=""
MODE="install"
DRY=0

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --hook) HOOK="${2:?--hook needs a path}"; shift 2 ;;
    --settings) SETTINGS="${2:?--settings needs a path}"; shift 2 ;;
    --project) SETTINGS="$(pwd)/.claude/settings.json"; shift ;;
    --remove | --uninstall) MODE="remove"; shift ;;
    --dry-run) DRY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "install-hooks.sh: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "install-hooks.sh: jq is required (e.g. 'brew install jq')." >&2
  exit 1
fi

if [ -z "$HOOK" ]; then
  HOOK="${CONFIG_DIR:-$HOME/.config/sketchybar}/clawd/clawd.hook.sh"
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"

if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "install-hooks.sh: $SETTINGS is not valid JSON; refusing to touch it." >&2
  exit 1
fi

# jq helper shared by both modes: drop any matcher-group whose commands mention
# our hook script (so re-install/path-change/remove are all clean).
STRIP='def strip(ev): (.hooks[ev] // []) | map(select(([.hooks[]? | (.command // "")] | any(test("clawd\\.hook\\.sh"))) | not));'

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if [ "$MODE" = "install" ]; then
  jq --arg hook "$HOOK" "
    $STRIP
    .hooks = (.hooks // {})
    | .hooks.SessionStart     = (strip(\"SessionStart\")     + [{hooks:[{type:\"command\", command:(\$hook+\" start\")}]}])
    | .hooks.UserPromptSubmit = (strip(\"UserPromptSubmit\") + [{hooks:[{type:\"command\", command:(\$hook+\" working\")}]}])
    | .hooks.Stop             = (strip(\"Stop\")             + [{hooks:[{type:\"command\", command:(\$hook+\" idle\")}]}])
    | .hooks.StopFailure      = (strip(\"StopFailure\")      + [{hooks:[{type:\"command\", command:(\$hook+\" error\")}]}])
    | .hooks.Notification     = (strip(\"Notification\")     + [{matcher:\"\", hooks:[{type:\"command\", command:(\$hook+\" notification\")}]}])
    | .hooks.SessionEnd       = (strip(\"SessionEnd\")       + [{hooks:[{type:\"command\", command:(\$hook+\" end\")}]}])
  " "$SETTINGS" >"$tmp"
else
  jq "
    $STRIP
    if (.hooks | type) != \"object\" then .
    else
      .hooks.SessionStart    = strip(\"SessionStart\")
      | .hooks.UserPromptSubmit = strip(\"UserPromptSubmit\")
      | .hooks.Stop          = strip(\"Stop\")
      | .hooks.StopFailure   = strip(\"StopFailure\")
      | .hooks.Notification  = strip(\"Notification\")
      | .hooks.SessionEnd    = strip(\"SessionEnd\")
      | .hooks |= with_entries(select(.value | length > 0))
      | if (.hooks | length) == 0 then del(.hooks) else . end
    end
  " "$SETTINGS" >"$tmp"
fi

if ! jq -e . "$tmp" >/dev/null 2>&1; then
  echo "install-hooks.sh: produced invalid JSON; aborting (no changes made)." >&2
  exit 1
fi

if [ "$DRY" = "1" ]; then
  echo "# --dry-run: resulting $SETTINGS would be:"
  cat "$tmp"
  exit 0
fi

# No-op? Don't churn a backup if nothing changed.
if jq -e --slurpfile new "$tmp" '. == $new[0]' "$SETTINGS" >/dev/null 2>&1; then
  echo "✓ no change needed — $SETTINGS already up to date"
  exit 0
fi

bak="$SETTINGS.clawd-bak.$(date +%s).$$"
cp "$SETTINGS" "$bak"
mv "$tmp" "$SETTINGS"
trap - EXIT

if [ "$MODE" = "install" ]; then
  echo "✓ installed clawd hooks into $SETTINGS"
  echo "  hook command: $HOOK"
else
  echo "✓ removed clawd hooks from $SETTINGS"
fi
echo "  backup: $bak"
