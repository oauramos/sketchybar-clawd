#!/bin/sh
# clawd.widget.sh — SketchyBar widget: a clawd mascot + one status dot per running
# Claude Code session.
#
# Add ONE line to your sketchybarrc (after `sketchybar --bar ...`):
#     source "$CONFIG_DIR/clawd/clawd.widget.sh"
# Optionally export CLAWD_* knobs before it (see clawd.lib.sh / README).

# Resolve this file's own directory across sh/bash/zsh (zsh-only syntax hidden
# behind eval). Falls back to $CONFIG_DIR/clawd, which SketchyBar always sets.
if [ -n "${BASH_SOURCE:-}" ]; then _clawd_src="${BASH_SOURCE}"
elif [ -n "${ZSH_VERSION:-}" ]; then eval '_clawd_src="${(%):-%x}"'
else _clawd_src="$0"; fi
CLAWD_DIR="$(cd "$(dirname "$_clawd_src")" 2>/dev/null && pwd)"
[ -f "$CLAWD_DIR/clawd.lib.sh" ] || CLAWD_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/clawd"

CLAWD_FRAMES_DIR="$CLAWD_DIR/frames"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=clawd.lib.sh
. "$CLAWD_DIR/clawd.lib.sh"
clawd_load_config

_clawd_state="$(clawd_state_dir)"
mkdir -p "$_clawd_state" "$(clawd_sessions_dir)"

# Recolor the sprite to CLAWD_COLOR (image mode). Shipped frames are the neutral
# default; any other color is rendered once by the bundled generator into a cached
# per-color dir (needs python3). Falls back to the shipped frames otherwise.
_want="$(printf '%s' "$CLAWD_COLOR" | tr '[:upper:]' '[:lower:]')"
_want_dead="$(printf '%s' "$CLAWD_DEAD_COLOR" | tr '[:upper:]' '[:lower:]')"
if [ "$CLAWD_STYLE" = "image" ] && { [ "$_want" != "$CLAWD_SHIPPED_COLOR" ] || [ "$_want_dead" != "$CLAWD_SHIPPED_DEAD" ]; }; then
  _gen=""
  for _c in "$CLAWD_DIR/gen-clawd.py" "$CLAWD_DIR/../tools/gen-clawd.py"; do
    [ -f "$_c" ] && { _gen="$_c"; break; }
  done
  _py="$(PATH="/usr/bin:$PATH" command -v python3 2>/dev/null || true)"
  _cdir="$_clawd_state/frames-$CLAWD_COLOR-$CLAWD_DEAD_COLOR"
  if [ -n "$_gen" ] && [ -n "$_py" ]; then
    [ -f "$_cdir/clawd-open.png" ] || "$_py" "$_gen" --out "$_cdir" \
      --color "$CLAWD_COLOR" --dead-color "$CLAWD_DEAD_COLOR" >/dev/null 2>&1
    [ -f "$_cdir/clawd-open.png" ] && CLAWD_FRAMES_DIR="$_cdir"
  fi
  clawd_load_config
fi

# Persist resolved config for the daemon-spawned plugin (rc exports don't reach it).
{
  echo "CLAWD_STYLE=$CLAWD_STYLE"
  echo "CLAWD_FG=$CLAWD_FG"
  echo "CLAWD_FRAME_MS=$CLAWD_FRAME_MS"
  echo "CLAWD_FRAMES_DIR=$CLAWD_FRAMES_DIR"
  echo "CLAWD_SHOW_DOTS=$CLAWD_SHOW_DOTS"
  echo "CLAWD_DOT_IDLE=$CLAWD_DOT_IDLE"
  echo "CLAWD_DOT_WORK=$CLAWD_DOT_WORK"
  echo "CLAWD_DOT_WAIT=$CLAWD_DOT_WAIT"
  echo "CLAWD_DOT_SEP=$CLAWD_DOT_SEP"
  echo "CLAWD_SESSION_TTL=$CLAWD_SESSION_TTL"
} >"$_clawd_state/clawd.env"

_plugin="$CLAWD_DIR/clawd.plugin.sh"
_pos="$CLAWD_POSITION"

_add_mascot() {
  if [ "$CLAWD_STYLE" = "image" ]; then
    sketchybar --add item clawd "$_pos" \
      --set clawd background.image="$CLAWD_IDLE" background.image.scale="$CLAWD_IMG_SCALE" \
                  background.image.drawing=on background.color=0x00000000 \
                  icon.drawing=off label.drawing=off \
                  width="$CLAWD_IMG_WIDTH" padding_left="$CLAWD_IMG_PAD_LEFT" \
                  script="$_plugin" \
      --subscribe clawd claude_state
  else
    sketchybar --add item clawd "$_pos" \
      --set clawd icon="$CLAWD_IDLE" icon.font="$CLAWD_ICON_FONT" icon.color="$CLAWD_FG" \
                  icon.padding_left=8 icon.padding_right=6 label.drawing=off \
                  script="$_plugin" \
      --subscribe clawd claude_state
  fi
}
_add_dots() {
  sketchybar --add item clawd.sessions "$_pos" \
    --set clawd.sessions icon.drawing=off label="" \
                         label.font="$CLAWD_DOT_FONT" label.color="$CLAWD_DOT_COLOR" \
                         label.padding_left=4 label.padding_right=8
}

sketchybar --add event claude_state

# visual order, left -> right: [clawd] [dots]. Right side lays out right-to-left.
if [ "$_pos" = "right" ]; then
  [ "$CLAWD_SHOW_DOTS" = "1" ] && _add_dots
  _add_mascot
else
  _add_mascot
  [ "$CLAWD_SHOW_DOTS" = "1" ] && _add_dots
fi

sketchybar --add bracket clawd_box clawd '/clawd\..*/' \
  --set clawd_box background.color="$CLAWD_BG" background.border_color="$CLAWD_BORDER" \
                  background.border_width="$CLAWD_BORDER_WIDTH" \
                  background.corner_radius="$CLAWD_RADIUS" background.height="$CLAWD_HEIGHT"

# initial render (picks up any already-running sessions)
sketchybar --trigger claude_state
