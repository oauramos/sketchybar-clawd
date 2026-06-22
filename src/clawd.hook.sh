#!/bin/sh
# clawd.hook.sh — bridge from Claude Code hooks to the SketchyBar `claude_state`
# event. Configure your hooks (see hooks/install-hooks.sh) to call it as:
#
#     "$CONFIG_DIR/clawd/clawd.hook.sh" working
#     "$CONFIG_DIR/clawd/clawd.hook.sh" idle
#     "$CONFIG_DIR/clawd/clawd.hook.sh" notification    # reads stdin JSON .type
#
# Args: working | waiting | idle | notification
# It writes NOTHING to stdout (a Claude hook's stdout is fed back to the model),
# and always exits 0 so it can never block or fail a turn.

# The launchd-spawned environment and minimal hook environments may lack the
# dir that holds `sketchybar`; cover the common install locations.
export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/usr/bin:/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null)" || exit 0
[ -n "$SB" ] || exit 0

state=""
case "${1:-}" in
  working | waiting | idle)
    state="$1"
    ;;
  notification)
    # Branch on the notification subtype Claude Code passes on stdin.
    #   permission_prompt / elicitation_dialog -> Claude needs your input (waiting)
    #   idle_prompt                            -> Claude is done, awaiting prompt (idle)
    #   anything else (auth_success, ...)      -> ignore
    type="$(jq -r '.type // empty' 2>/dev/null)"
    case "$type" in
      permission_prompt | elicitation_dialog) state="waiting" ;;
      idle_prompt) state="idle" ;;
      *) exit 0 ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

"$SB" --trigger claude_state STATE="$state" >/dev/null 2>&1
exit 0
