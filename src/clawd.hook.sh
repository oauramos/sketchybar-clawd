#!/bin/sh
# clawd.hook.sh — bridge from Claude Code hooks to the per-session state store.
#
# Every hook event carries a `session_id` on stdin; this records that session's
# state under ~/.cache/sketchybar-clawd/sessions/<session_id> and pokes SketchyBar
# to redraw. One session = one status dot in the bar.
#
# Wire it (see hooks/install-hooks.sh) as:
#   SessionStart    -> clawd.hook.sh start
#   UserPromptSubmit-> clawd.hook.sh working
#   Stop            -> clawd.hook.sh idle
#   StopFailure     -> clawd.hook.sh error    (API error -> clawd keels over)
#   Notification    -> clawd.hook.sh notification   (reads .type)
#   SessionEnd      -> clawd.hook.sh end
#
# Writes nothing to stdout (a hook's stdout is fed back to Claude); always exit 0.

export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/usr/bin:/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null)" || exit 0
[ -n "$SB" ] || exit 0

SESS="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar-clawd/sessions"
mkdir -p "$SESS" 2>/dev/null

json="$(cat 2>/dev/null)"
sid="$(printf '%s' "$json" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$sid" ] || exit 0
case "$sid" in *[!A-Za-z0-9._-]*) exit 0 ;; esac   # keep it a safe filename

case "${1:-}" in
  start | idle) printf 'idle' >"$SESS/$sid" ;;
  working) printf 'working' >"$SESS/$sid" ;;
  waiting) printf 'waiting' >"$SESS/$sid" ;;
  error) printf 'error' >"$SESS/$sid" ;;
  notification)
    type="$(printf '%s' "$json" | jq -r '.type // empty' 2>/dev/null)"
    case "$type" in
      permission_prompt | elicitation_dialog) printf 'waiting' >"$SESS/$sid" ;;
      idle_prompt) printf 'idle' >"$SESS/$sid" ;;
      *) exit 0 ;;
    esac ;;
  end) rm -f "$SESS/$sid" ;;
  *) exit 0 ;;
esac

"$SB" --trigger claude_state >/dev/null 2>&1
exit 0
