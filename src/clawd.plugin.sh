#!/bin/sh
# clawd.plugin.sh — SketchyBar item script for the clawd Claude Code mascot(s).
#
# Runs on the forced initial load and on every `claude_state` event, reads the
# per-session state store, and renders one of two layouts (CLAWD_MODE):
#   herd  — one clawd PER session, each acting out its own state (hammering,
#           arm-up waving, dead, asleep), capped at CLAWD_HERD_MAX then "+K".
#   hero  — a single mascot reflecting the most-urgent session, plus a glyph
#           strip with one glyph per session, urgency-sorted and capped.
# Either cap yields to the runtime one `sketchybar-clawd N` leaves in the state
# dir (see clawd_cap_override), so the herd can grow or shrink without a reload.
# Either way the box border turns orange while any session is waiting on you, and
# a session running subagents wears their count as a badge over its head. Sessions
# idle past CLAWD_HIBERNATE_AFTER fold into ONE hibernation clawd (hero: one
# "z<N>" strip entry) wearing their count the same way, outside the cap.
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
# `sketchybar-clawd N` overrides both caps. The herd can't outgrow the slots the
# widget created (CLAWD_HERD_POOL); the command reloads when N needs more.
_cap="$(clawd_cap_override)"
[ -z "$_cap" ] || { CLAWD_HERD_MAX="$_cap"; CLAWD_STRIP_MAX="$_cap"; }
[ "$CLAWD_HERD_MAX" -le "$CLAWD_HERD_POOL" ] || CLAWD_HERD_MAX="$CLAWD_HERD_POOL"
PIDFILE="$STATE_DIR/anim.pid"
ANIM_STATE="$STATE_DIR/anim.state"      # hero worker: line1 interval s, line2 frames
HPIDFILE="$STATE_DIR/herd.pid"
MULTI="$STATE_DIR/multi.state"          # herd worker: "<item> <frame0> <frame1>" per line
BOX="clawd_box"                          # bracket name (see clawd.widget.sh)
SESS="$(clawd_sessions_dir)"; mkdir -p "$SESS"
AGENTS="$(clawd_agents_dir)"            # agents/<session_id>/<agent_id> per live subagent
OWNERS="$(clawd_owners_dir)"            # owners/<session_id> = "<pid> <start>" of its CLI

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

# Live subagents for session $1, pruning registrations whose SubagentStop never
# landed (killed session, crashed CLI) so a leak can't pin the badge on forever.
agent_count() {  # $1 session id -> N
  _adir="$AGENTS/$1"; _an=0
  if [ -d "$_adir" ]; then
    for _af in "$_adir"/*; do
      [ -f "$_af" ] || continue
      _amt="$(stat -f %m "$_af" 2>/dev/null || echo "$now")"
      if [ $((now - _amt)) -gt "$CLAWD_AGENT_TTL" ]; then rm -f "$_af"; continue; fi
      _an=$((_an + 1))
    done
  fi
  printf '%s' "$_an"
}

# A session whose Claude Code process is gone is a ghost: SessionEnd never fired
# (window closed, SIGKILL, crash), so nothing ever deleted its state file and it
# would keep drawing a clawd for a whole CLAWD_SESSION_TTL. Sessions with no
# owner stamp — recorded before this existed, or whose CLI the hook couldn't
# identify — fall back to the TTL alone.
session_liveness() {  # $1 session id -> 0 CLI gone, 1 CLI alive, 2 no usable stamp
  [ "${CLAWD_PID_CHECK:-1}" = "1" ] || return 2
  _of="$OWNERS/$1"; [ -f "$_of" ] || return 2
  _opid=""; _ostart=""
  read -r _opid _ostart <"$_of" 2>/dev/null
  case "${_opid:-}" in "" | *[!0-9]*) return 2 ;; esac
  _cur="$(ps -o lstart= -p "$_opid" 2>/dev/null | tr -s ' ' '_' | tr -d '\n')"
  [ -n "$_cur" ] || return 0                 # pid gone -> the CLI died
  [ "$_cur" = "$_ostart" ] || return 0       # pid recycled -> that is NOT our CLI
  return 1
}

# Should the session file $1 stop being drawn? When the session carries an owner
# stamp, the process is the authority: a CLI still running is a session still
# open, however long it has sat idle — a clawd parked asleep for a day is right,
# an empty slot for a live session is not. The TTL only ages out sessions we
# cannot tie to a process.
session_stale() {  # $1 session file path
  session_liveness "${1##*/}"
  case $? in 0) return 0 ;; 1) return 1 ;; esac
  _mt="$(stat -f %m "$1" 2>/dev/null || echo "$now")"
  [ $((now - _mt)) -gt "$CLAWD_SESSION_TTL" ]
}

# Forget a session completely: its state, its owner stamp, its subagents.
drop_session() {  # $1 session id
  rm -f "$SESS/$1" "$OWNERS/$1"
  rm -rf "$AGENTS/${1:?}"
}

# Claude Code's Stop hook fires while subagents are still running, so a session
# can read "idle" with agents mid-flight. Agents at work = the clawd is at work.
eff_state() {  # $1 raw state, $2 agent count -> state
  case "$1" in
    waiting | error) printf '%s' "$1" ;;                 # urgency wins over agents
    *) if [ "${2:-0}" -gt 0 ]; then printf 'working'; else printf '%s' "$1"; fi ;;
  esac
}

# Badge text for N running agents: "" when off/none, "3", or "9+" past the cap.
agent_badge() {  # $1 count
  [ "${CLAWD_SHOW_AGENTS:-1}" = "1" ] || return 0
  [ "${1:-0}" -gt 0 ] || return 0
  if [ "$1" -gt "$CLAWD_AGENT_MAX" ]; then printf '%s+' "$CLAWD_AGENT_MAX"
  else printf '%s' "$1"; fi
}

# Overlay an item's two badges: the agent count over the head and "?" when the
# session wants you. Font/color are baked in at item creation (clawd.widget.sh);
# here we set text and, in image mode, the width that pins each badge to its
# corner (icon = count top-left, label = "?" top-right). Glyph styles spend the
# icon on the mascot itself, so both share the label ("?", "2", "?2").
#
# SketchyBar only honors icon.align/label.align INSIDE a fixed width — an
# auto-width badge just lands wherever the content block falls, which put the
# count on the right, in the "?" corner. So hand each drawn badge an explicit
# slice of the item: alone it takes the whole width, together they split it.
set_badges() {  # $1 item, $2 state, $3 agent count
  _ask=""; [ "$2" = "waiting" ] && _ask="$CLAWD_ASK_GLYPH"
  _num="$(agent_badge "${3:-0}")"
  _lw=""                                    # optional "label.width=N" (image only)
  if [ "$CLAWD_STYLE" = "image" ]; then
    _iw="$CLAWD_IMG_WIDTH"; _lwn="$CLAWD_IMG_WIDTH"
    if [ -n "$_num" ] && [ -n "$_ask" ]; then
      _iw=$((CLAWD_IMG_WIDTH / 2)); _lwn=$((CLAWD_IMG_WIDTH - _iw))
    fi
    _lw="label.width=$_lwn"
    if [ -n "$_num" ]; then "$SB" --set "$1" icon="$_num" icon.width="$_iw" icon.drawing=on >/dev/null 2>&1
    else "$SB" --set "$1" icon.drawing=off >/dev/null 2>&1; fi
  else
    _ask="$_ask$_num"
  fi
  # shellcheck disable=SC2086  # $_lw is one optional bare argument, never empty-with-spaces
  if [ -n "$_ask" ]; then "$SB" --set "$1" label="$_ask" $_lw label.drawing=on >/dev/null 2>&1
  else "$SB" --set "$1" label.drawing=off >/dev/null 2>&1; fi
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
  n_wait=0; n_err=0; n_work=0; n_idle=0; total=0; n_agents=0; n_hib=0
  for f in "$SESS"/*; do
    [ -f "$f" ] || continue
    if session_stale "$f"; then drop_session "${f##*/}"; continue; fi
    ac="$(agent_count "${f##*/}")"          # file name = session id
    n_agents=$((n_agents + ac))             # hero badge = agents across all sessions
    st="$(eff_state "$(cat "$f" 2>/dev/null)" "$ac")"
    # long asleep -> one shared "z<count>" at the end of the strip, not a dot each
    if clawd_hibernating "$f" "$st" "$now"; then n_hib=$((n_hib + 1)); continue; fi
    case "$st" in
      waiting) n_wait=$((n_wait + 1)) ;;
      error)   n_err=$((n_err + 1)) ;;
      working) n_work=$((n_work + 1)) ;;
      *)       n_idle=$((n_idle + 1)) ;;
    esac
    total=$((total + 1))
  done

  # No sessions at all (image mode): a single neutral-white clawd just blinks as
  # a "start me" call to action — no sleep pose, no props, no status strip.
  if [ "$total" -eq 0 ] && [ "$n_hib" -eq 0 ] && [ "$CLAWD_STYLE" = "image" ]; then
    [ "${CLAWD_SHOW_DOTS:-1}" = "1" ] && "$SB" --set clawd.sessions label="" label.drawing=off >/dev/null 2>&1
    set_border "ok"; set_badges clawd "ok" 0
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
  [ "$n_hib" -gt 0 ] && STRIP_OUT="${STRIP_OUT:+$STRIP_OUT$CLAWD_DOT_SEP}$CLAWD_DOT_HIBERNATE$n_hib"
  if [ "${CLAWD_SHOW_DOTS:-1}" = "1" ]; then
    "$SB" --set clawd.sessions label="$STRIP_OUT" label.drawing=on >/dev/null 2>&1
  fi

  set_border "$top"; set_badges clawd "$top" "$n_agents"

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
  _all="$(for f in "$SESS"/*; do
    [ -f "$f" ] || continue
    session_stale "$f" && { drop_session "${f##*/}"; continue; }
    printf '%s %s\n' "$(stat -f %B "$f" 2>/dev/null || echo 0)" "$f"
  done | sort -n | awk '{ print $2 }')"
  # Sessions asleep past CLAWD_HIBERNATE_AFTER leave the line: they share the one
  # hibernation clawd, which wears their count, instead of holding a slot each —
  # so they never crowd the live ones into "+K". Waking up (a prompt, a resume)
  # rewrites the state file, and the session is back in its slot.
  _list=""; _hib=0
  for f in $_all; do
    if clawd_hibernating "$f" "$(eff_state "$(cat "$f" 2>/dev/null)" "$(agent_count "${f##*/}")")" "$now"; then
      _hib=$((_hib + 1))
    else
      _list="$_list$f
"
    fi
  done
  _count=0; for f in $_list; do _count=$((_count + 1)); done
  _shown="$_count"; [ "$_shown" -gt "$CLAWD_HERD_MAX" ] && _shown="$CLAWD_HERD_MAX"
  # The blinking call-to-action means nobody at all — not even someone hibernating.
  _nobody=0; [ "$_count" -eq 0 ] && [ "$_hib" -eq 0 ] && _nobody=1

  # Border alarm scans EVERY session, not just the visible ones — a waiting
  # session folded into the "+K" overflow must still glow the box orange.
  _anywait=0
  for f in $_all; do [ "$(cat "$f" 2>/dev/null)" = "waiting" ] && { _anywait=1; break; }; done

  # Pass 1: build the animated-slot manifest and publish it BEFORE setting any
  # slot image, so the worker stops touching a slot the instant it goes static
  # (otherwise a stale in-flight frame could clobber the static pose).
  : >"$MULTI.tmp"
  _i=0
  for f in $_list; do
    [ "$_i" -ge "$_shown" ] && break
    _hf="$(herd_frames "$(eff_state "$(cat "$f" 2>/dev/null)" "$(agent_count "${f##*/}")")")"
    [ -n "$_hf" ] && printf 'clawd.s%s %s\n' "$_i" "$_hf" >>"$MULTI.tmp"
    _i=$((_i + 1))
  done
  # No sessions: slot 0 becomes a blinking white call-to-action (open/closed eyes).
  [ "$_nobody" = "1" ] && printf 'clawd.s0 %s\n' "$BLINK_FRAMES" >>"$MULTI.tmp"
  mv "$MULTI.tmp" "$MULTI" 2>/dev/null

  # Pass 2: set each visible slot's pose + show it.
  _i=0
  for f in $_list; do
    [ "$_i" -ge "$_shown" ] && break
    _ac="$(agent_count "${f##*/}")"
    _st="$(eff_state "$(cat "$f" 2>/dev/null)" "$_ac")"; _hf="$(herd_frames "$_st")"
    if [ -n "$_hf" ]; then img_set "clawd.s$_i" "${_hf%% *}"
    else img_set "clawd.s$_i" "$(herd_static "$_st")"; fi
    set_badges "clawd.s$_i" "$_st" "$_ac"
    "$SB" --set "clawd.s$_i" drawing=on >/dev/null 2>&1
    _i=$((_i + 1))
  done
  # no sessions at all -> one white clawd blinking (call to action) — the worker
  # cycles its frames (manifest written above); seed the open frame + show it.
  if [ "$_nobody" = "1" ]; then
    img_set clawd.s0 "$BLINK_OPEN"; set_badges clawd.s0 "ok" 0
    "$SB" --set clawd.s0 drawing=on >/dev/null 2>&1; _i=1
  fi
  # Hide the rest of the pool in ONE call — it can be a couple of dozen slots.
  set --
  while [ "$_i" -lt "$CLAWD_HERD_POOL" ]; do set -- "$@" --set "clawd.s$_i" drawing=off; _i=$((_i + 1)); done
  [ "$#" -eq 0 ] || "$SB" "$@" >/dev/null 2>&1

  _over=$((_count - _shown))
  if [ "$_over" -gt 0 ]; then "$SB" --set clawd.more label="+$_over" label.drawing=on drawing=on >/dev/null 2>&1
  else "$SB" --set clawd.more drawing=off >/dev/null 2>&1; fi

  # The hibernation clawd: asleep, with how many it stands for over its head —
  # where a working clawd wears its agent count (the badge look is baked in by
  # the widget). Shown even for one, so it never passes for an ordinary nap.
  if [ "$_hib" -gt 0 ]; then
    img_set clawd.hibernate "$CLAWD_F_SLEEP"
    "$SB" --set clawd.hibernate icon="$_hib" drawing=on >/dev/null 2>&1
  else "$SB" --set clawd.hibernate drawing=off >/dev/null 2>&1; fi

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
