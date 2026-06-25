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

# Recolor the sprite per state (image mode). Each distinct color is rendered once
# by the bundled generator into a cached dir keyed by color + dead-color + art
# version (so sprite-art changes bust the cache). Needs python3; otherwise the
# shipped neutral frames are used. CLAWD_DIR_WORK/IDLE/WAIT feed clawd_load_config.
if [ "$CLAWD_STYLE" = "image" ]; then
  _gen=""
  for _c in "$CLAWD_DIR/gen-clawd.py" "$CLAWD_DIR/../tools/gen-clawd.py"; do
    [ -f "$_c" ] && { _gen="$_c"; break; }
  done
  _py="$(PATH="/usr/bin:$PATH" command -v python3 2>/dev/null || true)"
  _dead="$(printf '%s' "$CLAWD_DEAD_COLOR" | tr '[:upper:]' '[:lower:]')"

  # Echo a frames dir holding all poses in $1 (RRGGBB); generate+cache if needed.
  _frames_for() {
    _col="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    if [ "$_col" = "$CLAWD_SHIPPED_COLOR" ] && [ "$_dead" = "$CLAWD_SHIPPED_DEAD" ]; then
      printf '%s' "$CLAWD_FRAMES_DIR"; return    # shipped neutral default
    fi
    _cdir="$_clawd_state/frames-$_col-$_dead-v$CLAWD_ART_VER"
    if [ -n "$_gen" ] && [ -n "$_py" ] && [ ! -f "$_cdir/.complete" ]; then
      "$_py" "$_gen" --out "$_cdir" --color "$_col" --dead-color "$_dead" >/dev/null 2>&1 \
        && touch "$_cdir/.complete"
    fi
    if [ -f "$_cdir/.complete" ]; then printf '%s' "$_cdir"; else printf '%s' "$CLAWD_FRAMES_DIR"; fi
  }

  CLAWD_DIR_WORK="$(_frames_for "$CLAWD_COLOR_WORK")"
  CLAWD_DIR_IDLE="$(_frames_for "$CLAWD_COLOR_IDLE")"
  CLAWD_DIR_WAIT="$(_frames_for "$CLAWD_COLOR_WAIT")"
  CLAWD_FRAMES_DIR="$CLAWD_DIR_WAIT"             # single-dir fallback / hero default
  clawd_load_config
fi

# Persist resolved config for the daemon-spawned plugin (rc exports don't reach it).
{
  echo "CLAWD_STYLE=$CLAWD_STYLE"
  echo "CLAWD_MODE=$CLAWD_MODE"
  echo "CLAWD_HERD_MAX=$CLAWD_HERD_MAX"
  echo "CLAWD_HERD_MS=$CLAWD_HERD_MS"
  echo "CLAWD_FG=$CLAWD_FG"
  echo "CLAWD_FRAME_MS=$CLAWD_FRAME_MS"
  echo "CLAWD_BLINK_MS=$CLAWD_BLINK_MS"
  echo "CLAWD_ASK_GLYPH=$CLAWD_ASK_GLYPH"
  echo "CLAWD_FRAMES_DIR=$CLAWD_FRAMES_DIR"
  echo "CLAWD_DIR_WORK=${CLAWD_DIR_WORK:-$CLAWD_FRAMES_DIR}"
  echo "CLAWD_DIR_IDLE=${CLAWD_DIR_IDLE:-$CLAWD_FRAMES_DIR}"
  echo "CLAWD_DIR_WAIT=${CLAWD_DIR_WAIT:-$CLAWD_FRAMES_DIR}"
  echo "CLAWD_SHOW_DOTS=$CLAWD_SHOW_DOTS"
  echo "CLAWD_DOT_IDLE=$CLAWD_DOT_IDLE"
  echo "CLAWD_DOT_WORK=$CLAWD_DOT_WORK"
  echo "CLAWD_DOT_WAIT=$CLAWD_DOT_WAIT"
  echo "CLAWD_DOT_ERR=$CLAWD_DOT_ERR"
  echo "CLAWD_DOT_SEP=$CLAWD_DOT_SEP"
  echo "CLAWD_STRIP_MAX=$CLAWD_STRIP_MAX"
  echo "CLAWD_BORDER=$CLAWD_BORDER"
  echo "CLAWD_BORDER_WAIT=$CLAWD_BORDER_WAIT"
  echo "CLAWD_SESSION_TTL=$CLAWD_SESSION_TTL"
} >"$_clawd_state/clawd.env"

_plugin="$CLAWD_DIR/clawd.plugin.sh"
_pos="$CLAWD_POSITION"

_add_mascot() {
  if [ "$CLAWD_STYLE" = "image" ]; then
    sketchybar --add item clawd "$_pos" \
      --set clawd background.image="$CLAWD_IDLE" background.image.scale="$CLAWD_IMG_SCALE" \
                  background.image.drawing=on background.color=0x00000000 \
                  icon.drawing=off \
                  label.font="$CLAWD_ASK_FONT" label.color="$CLAWD_ASK_COLOR" \
                  label.align=right label.y_offset="$CLAWD_ASK_YOFF" \
                  label.padding_right=3 label.drawing=off \
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

# --- herd mode: a fixed pool of slot items + an overflow counter -------------
_add_slot() {  # $1 = slot index
  sketchybar --add item "clawd.s$1" "$_pos" \
    --set "clawd.s$1" background.image="$CLAWD_F_SLEEP" background.image.scale="$CLAWD_IMG_SCALE" \
                      background.image.drawing=on background.color=0x00000000 \
                      icon.drawing=off \
                      label.font="$CLAWD_ASK_FONT" label.color="$CLAWD_ASK_COLOR" \
                      label.align=right label.y_offset="$CLAWD_ASK_YOFF" \
                      label.padding_right=3 label.drawing=off \
                      width="$CLAWD_IMG_WIDTH" padding_left="$CLAWD_IMG_PAD_LEFT" drawing=off
}
_add_more() {
  sketchybar --add item clawd.more "$_pos" \
    --set clawd.more icon.drawing=off label="" label.drawing=off \
                     label.font="$CLAWD_DOT_FONT" label.color="$CLAWD_DOT_COLOR" \
                     label.padding_left=4 label.padding_right=8 drawing=off
}
_add_herd() {
  # invisible driver: always processes claude_state and manages the slots
  sketchybar --add item clawd "$_pos" \
    --set clawd drawing=off width=0 updates=on icon.drawing=off label.drawing=off \
                background.drawing=off script="$_plugin" \
    --subscribe clawd claude_state
  # Slot order: right side lays out right-to-left, so add overflow + high indices
  # first to keep visual order s0,s1,…,+K from left to right.
  if [ "$_pos" = "right" ]; then
    _add_more
    _k=$((CLAWD_HERD_MAX - 1)); while [ "$_k" -ge 0 ]; do _add_slot "$_k"; _k=$((_k - 1)); done
  else
    _k=0; while [ "$_k" -lt "$CLAWD_HERD_MAX" ]; do _add_slot "$_k"; _k=$((_k + 1)); done
    _add_more
  fi
}

sketchybar --add event claude_state

if [ "$CLAWD_MODE" = "herd" ] && [ "$CLAWD_STYLE" = "image" ]; then
  _add_herd
  # explicit member list (sketchybar's regex doesn't do alternation)
  _box_members="clawd.more"
  _k=0; while [ "$_k" -lt "$CLAWD_HERD_MAX" ]; do _box_members="clawd.s$_k $_box_members"; _k=$((_k + 1)); done
else
  # hero — visual order left -> right: [clawd] [dots]. Right lays out right-to-left.
  if [ "$_pos" = "right" ]; then
    [ "$CLAWD_SHOW_DOTS" = "1" ] && _add_dots
    _add_mascot
  else
    _add_mascot
    [ "$CLAWD_SHOW_DOTS" = "1" ] && _add_dots
  fi
  _box_members="clawd /clawd\..*/"
fi

# shellcheck disable=SC2086
sketchybar --add bracket clawd_box $_box_members \
  --set clawd_box background.color="$CLAWD_BG" background.border_color="$CLAWD_BORDER" \
                  background.border_width="$CLAWD_BORDER_WIDTH" \
                  background.corner_radius="$CLAWD_RADIUS" background.height="$CLAWD_HEIGHT"

# initial render (picks up any already-running sessions)
sketchybar --trigger claude_state
