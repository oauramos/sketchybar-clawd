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
# Every state write also stamps owners/<session_id> with the pid of the Claude
# Code process this hook is running under. SessionEnd is the only event that
# removes a session, and a CLI that dies hard never fires it — so the widget
# checks that pid and drops the orphan instead of drawing a ghost clawd until
# CLAWD_SESSION_TTL runs out.
#
# Writes nothing to stdout (a hook's stdout is fed back to Claude); always exit 0.

export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/usr/bin:/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null)" || exit 0
[ -n "$SB" ] || exit 0

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar-clawd"
SESS="$CACHE/sessions"
AGENTS="$CACHE/agents"
OWNERS="$CACHE/owners"
mkdir -p "$SESS" 2>/dev/null

# An id has to be a safe single path component: no separators, and never "." or
# ".." (which would aim the agent-dir cleanup at its parent).
safe_id() {
  [ -n "${1:-}" ] || return 1
  case "$1" in
    . | .. | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

# --- session owner (the Claude Code process this hook hangs off) -------------

# Normalized start time of $1, empty when that pid is gone. Pairing it with the
# pid is what makes a RECYCLED pid read as dead rather than reviving a ghost.
proc_start() {  # $1 pid -> start stamp
  ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' '_' | tr -d '\n'
}

# True when $1 looks like the Claude Code CLI: installed as `claude`, or a
# JS runtime running it.
is_claude() {  # $1 pid
  _c="$(ps -o comm= -p "$1" 2>/dev/null)"
  case "${_c##*/}" in
    claude) return 0 ;;
    node | bun | deno) ;;
    *) return 1 ;;
  esac
  ps -o args= -p "$1" 2>/dev/null | grep -q claude
}

# Claude Code registers every running CLI at ~/.claude/sessions/<pid>.json,
# carrying the session id it serves — a direct session -> pid map that needs no
# knowledge of how this hook was spawned. grep narrows the candidates to the
# files that mention $sid at all (safe_id already made it a fixed string), jq
# then confirms the match is the sessionId field and not some other value.
registry_pid() {
  _reg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
  [ -d "$_reg" ] || return 1
  for _rf in $(grep -lF -- "$sid" "$_reg"/*.json 2>/dev/null); do
    _rp="${_rf##*/}"; _rp="${_rp%.json}"
    case "$_rp" in "" | *[!0-9]*) continue ;; esac
    [ "$(jq -r '.sessionId // empty' "$_rf" 2>/dev/null)" = "$sid" ] || continue
    is_claude "$_rp" && { printf '%s' "$_rp"; return 0; }
  done
  return 1
}

# The CLI exports its own pid to hooks; next best is its session registry; last
# resort is walking up from this hook, which the CLI spawned. Failing all three,
# print nothing — the widget then falls back to ageing the session out on
# CLAWD_SESSION_TTL, exactly as it always did.
owner_pid() {
  case "${CLAUDE_PID:-}" in
    "" | *[!0-9]*) ;;
    *) is_claude "$CLAUDE_PID" && { printf '%s' "$CLAUDE_PID"; return 0; } ;;
  esac
  registry_pid && return 0
  _p="${PPID:-$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')}"
  _i=0
  while [ "$_i" -lt 12 ]; do
    case "${_p:-}" in "" | 0 | 1 | *[!0-9]*) return 1 ;; esac
    is_claude "$_p" && { printf '%s' "$_p"; return 0; }
    _p="$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')"
    _i=$((_i + 1))
  done
  return 1
}

# Stamp owners/<sid> with "<pid> <start>". An owner we cannot identify clears the
# stamp rather than leaving a stale one behind — a wrong pid is worse than none,
# since some unrelated process could keep the ghost alive (or kill a live clawd).
record_owner() {
  _op="$(owner_pid)" && _os="$(proc_start "$_op")" && [ -n "$_os" ] || {
    rm -f "$OWNERS/$sid" 2>/dev/null
    return 0
  }
  mkdir -p "$OWNERS" 2>/dev/null
  printf '%s %s\n' "$_op" "$_os" >"$OWNERS/$sid"
}

json="$(cat 2>/dev/null)"
sid="$(printf '%s' "$json" | jq -r '.session_id // empty' 2>/dev/null)"
safe_id "$sid" || exit 0

# Record a state AND re-stamp who owns the session, so the owner pid tracks a
# resumed session onto its new CLI process.
set_state() {  # $1 state
  printf '%s' "$1" >"$SESS/$sid"
  record_owner
}

case "${1:-}" in
  start)
    set_state idle
    # A fresh or resumed session has no live agents; a compacted one may still
    # have some running, so leave that registry alone.
    [ "$(printf '%s' "$json" | jq -r '.source // empty' 2>/dev/null)" = "compact" ] \
      || rm -rf "$AGENTS/${sid:?}" ;;
  idle) set_state idle ;;
  working) set_state working ;;
  waiting) set_state waiting ;;
  error) set_state error ;;
  notification)
    type="$(printf '%s' "$json" | jq -r '.type // empty' 2>/dev/null)"
    case "$type" in
      permission_prompt | elicitation_dialog) set_state waiting ;;
      idle_prompt) set_state idle ;;
      *) exit 0 ;;
    esac ;;
  agent-start)
    aid="$(printf '%s' "$json" | jq -r '.agent_id // empty' 2>/dev/null)"
    safe_id "$aid" || exit 0
    mkdir -p "$AGENTS/$sid" 2>/dev/null
    : >"$AGENTS/$sid/$aid"
    record_owner ;;
  agent-stop)
    aid="$(printf '%s' "$json" | jq -r '.agent_id // empty' 2>/dev/null)"
    safe_id "$aid" || exit 0
    rm -f "$AGENTS/$sid/$aid"
    rmdir "$AGENTS/$sid" 2>/dev/null ;;   # tidy once the last agent is gone
  end) rm -f "$SESS/$sid" "$OWNERS/$sid"; rm -rf "$AGENTS/${sid:?}" ;;
  *) exit 0 ;;
esac

"$SB" --trigger claude_state >/dev/null 2>&1
exit 0
