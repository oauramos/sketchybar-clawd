#!/bin/sh
# clawd.widget.sh — SketchyBar widget definition for the clawd Claude Code mascot.
#
# Add ONE line to your sketchybarrc (after `sketchybar --bar ...`):
#
#     source "$CONFIG_DIR/clawd/clawd.widget.sh"
#
# Optionally export CLAWD_* knobs before that line to customize (see clawd.lib.sh
# / README). This file registers the `claude_state` event, the mascot item, the
# status segments, and a self-styled bracket. Safe to source from sh/bash/zsh.

# Resolve this file's own directory across sh/bash/zsh. The zsh-only expansion is
# hidden behind `eval` so it never trips bash's/sh's parser (it would otherwise be
# a syntax error even inside the unused branch). Falls back to $CONFIG_DIR/clawd,
# which SketchyBar always sets at runtime.
if [ -n "${BASH_SOURCE:-}" ]; then
  _clawd_src="${BASH_SOURCE}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  eval '_clawd_src="${(%):-%x}"'
else
  _clawd_src="$0"
fi
CLAWD_DIR="$(cd "$(dirname "$_clawd_src")" 2>/dev/null && pwd)"
[ -f "$CLAWD_DIR/clawd.lib.sh" ] || CLAWD_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/clawd"

CLAWD_FRAMES_DIR="$CLAWD_DIR/frames"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=clawd.lib.sh
. "$CLAWD_DIR/clawd.lib.sh"
clawd_load_config

# Persist the resolved config so the daemon-spawned plugin sees the same
# settings (the rc's exported vars do not reach plugin processes).
_clawd_state="$(clawd_state_dir)"
mkdir -p "$_clawd_state"
{
  echo "CLAWD_STYLE=$CLAWD_STYLE"
  echo "CLAWD_FG=$CLAWD_FG"
  echo "CLAWD_MUTED=$CLAWD_MUTED"
  echo "CLAWD_FRAME_MS=$CLAWD_FRAME_MS"
  echo "CLAWD_SHOW_LABELS=$CLAWD_SHOW_LABELS"
} >"$_clawd_state/clawd.env"

_clawd_plugin="$CLAWD_DIR/clawd.plugin.sh"
_pos="$CLAWD_POSITION"

# --- item builders -----------------------------------------------------------
_clawd_add_mascot() {
  if [ "$CLAWD_STYLE" = "image" ]; then
    # pixel-art sprite via background.image; fixed width so the image isn't clipped
    sketchybar --add item clawd "$_pos" \
      --set clawd background.image="$CLAWD_IDLE" \
                  background.image.scale="$CLAWD_IMG_SCALE" \
                  background.image.drawing=on \
                  background.color=0x00000000 \
                  icon.drawing=off label.drawing=off \
                  width="$CLAWD_IMG_WIDTH" \
                  script="$_clawd_plugin" \
      --subscribe clawd claude_state
  else
    sketchybar --add item clawd "$_pos" \
      --set clawd icon="$CLAWD_IDLE" \
                  icon.font="$CLAWD_ICON_FONT" \
                  icon.color="$CLAWD_FG" \
                  icon.padding_left=8 icon.padding_right=6 \
                  label.drawing=off \
                  script="$_clawd_plugin" \
      --subscribe clawd claude_state
  fi
}

_clawd_add_label() { # $1=item  $2=text  $3=color  $4=pad_right
  sketchybar --add item "$1" "$_pos" \
    --set "$1" icon.drawing=off \
               label="$2" label.font="$CLAWD_LABEL_FONT" label.color="$3" \
               label.padding_left=2 label.padding_right="$4"
}

_clawd_add_sep() { # $1=item
  sketchybar --add item "$1" "$_pos" \
    --set "$1" label.drawing=off \
               icon="$CLAWD_SEP" icon.font="$CLAWD_LABEL_FONT" icon.color="$CLAWD_SEP_COLOR" \
               icon.padding_left=2 icon.padding_right=2
}

# --- assemble ----------------------------------------------------------------
# Register the custom event BEFORE subscribing (SketchyBar silently ignores
# subscriptions to unknown events).
sketchybar --add event claude_state

# Desired visual order, left -> right:  clawd  idle · working · waiting
# For the `right` side, items are laid out right-to-left in add order, so add the
# group in reverse there; left/center add left-to-right.
if [ "$CLAWD_SHOW_LABELS" = "1" ]; then
  if [ "$_pos" = "right" ]; then
    _clawd_add_label clawd.wait "$CLAWD_LABEL_WAIT" "$CLAWD_MUTED" 8
    _clawd_add_sep   clawd.s2
    _clawd_add_label clawd.work "$CLAWD_LABEL_WORK" "$CLAWD_MUTED" 4
    _clawd_add_sep   clawd.s1
    _clawd_add_label clawd.idle "$CLAWD_LABEL_IDLE" "$CLAWD_FG"   4
    _clawd_add_mascot
  else
    _clawd_add_mascot
    _clawd_add_label clawd.idle "$CLAWD_LABEL_IDLE" "$CLAWD_FG"   4
    _clawd_add_sep   clawd.s1
    _clawd_add_label clawd.work "$CLAWD_LABEL_WORK" "$CLAWD_MUTED" 4
    _clawd_add_sep   clawd.s2
    _clawd_add_label clawd.wait "$CLAWD_LABEL_WAIT" "$CLAWD_MUTED" 8
  fi
else
  _clawd_add_mascot
fi

# Group into a self-styled bracket so it looks consistent on a bare bar.
sketchybar --add bracket clawd_box clawd '/clawd\..*/' \
  --set clawd_box background.color="$CLAWD_BG" \
                  background.border_color="$CLAWD_BORDER" \
                  background.border_width="$CLAWD_BORDER_WIDTH" \
                  background.corner_radius="$CLAWD_RADIUS" \
                  background.height="$CLAWD_HEIGHT"

# Paint the initial state.
sketchybar --trigger claude_state STATE=idle
