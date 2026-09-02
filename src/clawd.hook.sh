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
#   SubagentStart   -> clawd.hook.sh agent-start    (a /agents subagent spawned)
#   SubagentStop    -> clawd.hook.sh agent-stop
#   SessionEnd      -> clawd.hook.sh end
#
# Subagents get their own registry: one empty file per running agent under
# agents/<session_id>/<agent_id>, so the file count is the live agent count for
# that session (rendered as a number over the clawd's head). Both subagent events
# carry the PARENT session_id, so agents land on the right clawd.
#
# Writes nothing to stdout (a hook's stdout is fed back to Claude); always exit 0.

export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/usr/bin:/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null)" || exit 0
[ -n "$SB" ] || exit 0

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar-clawd"
SESS="$CACHE/sessions"
AGENTS="$CACHE/agents"
mkdir -p "$SESS" 2>/dev/null

# An id has to be a safe single path component: no separators, and never "." or
# ".." (which would aim the agent-dir cleanup at its parent).
safe_id() {
  [ -n "${1:-}" ] || return 1
  case "$1" in
    . | .. | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

json="$(cat 2>/dev/null)"
sid="$(printf '%s' "$json" | jq -r '.session_id // empty' 2>/dev/null)"
safe_id "$sid" || exit 0

case "${1:-}" in
  start)
    printf 'idle' >"$SESS/$sid"
    # A fresh or resumed session has no live agents; a compacted one may still
    # have some running, so leave that registry alone.
    [ "$(printf '%s' "$json" | jq -r '.source // empty' 2>/dev/null)" = "compact" ] \
      || rm -rf "$AGENTS/$sid" ;;
  idle) printf 'idle' >"$SESS/$sid" ;;
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
  agent-start)
    aid="$(printf '%s' "$json" | jq -r '.agent_id // empty' 2>/dev/null)"
    safe_id "$aid" || exit 0
    mkdir -p "$AGENTS/$sid" 2>/dev/null
    : >"$AGENTS/$sid/$aid" ;;
  agent-stop)
    aid="$(printf '%s' "$json" | jq -r '.agent_id // empty' 2>/dev/null)"
    safe_id "$aid" || exit 0
    rm -f "$AGENTS/$sid/$aid"
    rmdir "$AGENTS/$sid" 2>/dev/null ;;   # tidy once the last agent is gone
  end) rm -f "$SESS/$sid"; rm -rf "$AGENTS/$sid" ;;
  *) exit 0 ;;
esac

"$SB" --trigger claude_state >/dev/null 2>&1
exit 0
