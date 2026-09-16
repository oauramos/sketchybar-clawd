#!/usr/bin/env bash
# install.sh — install the clawd SketchyBar widget.
#
# Copies the widget into your SketchyBar config, helps wire it into your
# sketchybarrc, links the `sketchybar-clawd` command onto your PATH, and
# (optionally) installs the Claude Code hooks. Idempotent and non-destructive:
# it backs up before editing and never overwrites your config.
#
# Usage:
#   ./install.sh [options]
#     --config-dir DIR   SketchyBar config dir (default: $XDG_CONFIG_HOME/sketchybar
#                        or ~/.config/sketchybar)
#     --bin-dir DIR      Where to link the `sketchybar-clawd` command
#                        (default: ~/.local/bin)
#     --no-command       Don't link the `sketchybar-clawd` command
#     --yes, -y          Assume "yes" to all prompts (non-interactive)
#     --with-hooks       Install the Claude Code hooks without prompting
#     --no-hooks         Skip the Claude Code hooks
#     --link             Symlink the widget files instead of copying (for dev)
#     --print-only       Show what would happen; change nothing
#     -h, --help         This help
set -euo pipefail

# Installs into the calling user's $HOME (.config/sketchybar, ~/.claude). Running
# under sudo would create root-owned files that lock the real user out, so refuse.
if [ "$(id -u)" -eq 0 ]; then
  echo "install.sh: refusing to run as root — it installs into your \$HOME; run as your normal user (no sudo)." >&2
  exit 1
fi

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SELF/src"

CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
ASSUME_YES=0
HOOKS_MODE="ask"   # ask | yes | no
COMMAND=1
LINK=0
PRINT_ONLY=0

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) CONFIG_DIR="${2:?--config-dir needs a path}"; shift 2 ;;
    --bin-dir) BIN_DIR="${2:?--bin-dir needs a path}"; shift 2 ;;
    --no-command) COMMAND=0; shift ;;
    -y | --yes) ASSUME_YES=1; shift ;;
    --with-hooks) HOOKS_MODE="yes"; shift ;;
    --no-hooks) HOOKS_MODE="no"; shift ;;
    --link) LINK=1; shift ;;
    --print-only | --dry-run) PRINT_ONLY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "install.sh: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

DEST="$CONFIG_DIR/clawd"
RC="$CONFIG_DIR/sketchybarrc"
# Intentionally a literal $CONFIG_DIR — this is written verbatim into the rc.
# shellcheck disable=SC2016
SOURCE_LINE='source "$CONFIG_DIR/clawd/clawd.widget.sh"'
FILES="clawd.lib.sh clawd.widget.sh clawd.plugin.sh clawd.hook.sh clawd.ctl.sh"
CMD="$BIN_DIR/sketchybar-clawd"

say()  { printf '%s\n' "$*"; }
step() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

confirm() { # confirm "question" -> 0 if yes
  [ "$ASSUME_YES" = "1" ] && return 0
  [ -r /dev/tty ] || return 1     # non-interactive: treat as "no"
  printf '%s [y/N] ' "$1" >/dev/tty
  local ans; read -r ans </dev/tty || return 1
  case "$ans" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# --- locate sketchybar -------------------------------------------------------
export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:$PATH"
SB="$(command -v sketchybar 2>/dev/null || true)"
if [ -z "$SB" ]; then
  warn "sketchybar not found on PATH. Install it first (https://github.com/FelixKratz/SketchyBar)."
  warn "Continuing anyway — the widget files will be placed, but nothing will render yet."
fi

step "clawd installer"
say  "  source:     $SRC"
say  "  config dir: $CONFIG_DIR"
say  "  install to: $DEST  ($([ "$LINK" = 1 ] && echo symlink || echo copy))"
say  ""

# --- 1. place widget files ---------------------------------------------------
step "Installing widget files -> $DEST"
if [ "$PRINT_ONLY" = "1" ]; then
  for f in $FILES; do say "  would place $DEST/$f"; done
  say "  would place $DEST/frames/ (clawd sprite PNGs)"
else
  mkdir -p "$DEST"
  for f in $FILES; do
    rm -f "$DEST/$f"
    if [ "$LINK" = "1" ]; then
      ln -s "$SRC/$f" "$DEST/$f"
    else
      cp "$SRC/$f" "$DEST/$f"
    fi
  done
  # mascot sprite frames (image mode)
  rm -rf "$DEST/frames"
  if [ "$LINK" = "1" ]; then
    ln -s "$SRC/frames" "$DEST/frames"
  else
    cp -R "$SRC/frames" "$DEST/frames"
  fi
  # sprite generator, so CLAWD_COLOR can recolor at runtime
  cp "$SELF/tools/gen-clawd.py" "$DEST/gen-clawd.py" 2>/dev/null || true
  chmod +x "$DEST"/*.sh
  say "  done."
fi
say ""

# --- 2. the `sketchybar-clawd` command --------------------------------------
# A symlink, so `sketchybar-clawd 12` (change how many clawds show before "+K")
# always runs the installed widget's own copy.
step "Linking the sketchybar-clawd command -> $CMD"
if [ "$COMMAND" = "0" ]; then
  say "  skipped (--no-command). Link it yourself later:"
  say "      ln -s \"$DEST/clawd.ctl.sh\" \"$CMD\""
elif [ "$PRINT_ONLY" = "1" ]; then
  say "  would link $CMD -> $DEST/clawd.ctl.sh"
elif [ -e "$CMD" ] && [ ! -L "$CMD" ]; then
  warn "$CMD exists and is not a symlink — leaving it alone. Link it yourself:"
  say  "      ln -s \"$DEST/clawd.ctl.sh\" \"$CMD\""
elif confirm "  Link the command into $BIN_DIR?"; then
  if mkdir -p "$BIN_DIR" 2>/dev/null && ln -sfn "$DEST/clawd.ctl.sh" "$CMD" 2>/dev/null; then
    say "  done."
    case ":$PATH:" in
      *":$BIN_DIR:"*) ;;
      *) warn "$BIN_DIR is not on your PATH — add it, or re-run with --bin-dir DIR for one that is." ;;
    esac
  else
    warn "could not write $CMD — link it yourself from a dir on your PATH:"
    say  "      ln -s \"$DEST/clawd.ctl.sh\" \"$CMD\""
  fi
else
  say "  skipped. Link it yourself later:"
  say "      ln -s \"$DEST/clawd.ctl.sh\" \"$CMD\""
fi
say ""

# --- 3. wire into sketchybarrc ----------------------------------------------
step "Wiring into sketchybarrc"
if grep -qs 'clawd/clawd.widget.sh' "$RC" 2>/dev/null; then
  say "  already sourced in $RC — nothing to do."
elif [ "$PRINT_ONLY" = "1" ]; then
  say "  would add this line to $RC:"
  say "      $SOURCE_LINE"
elif [ -f "$RC" ] && [ -w "$RC" ]; then
  if confirm "  Append the source line to $RC?"; then
    cp "$RC" "$RC.clawd-bak.$(date +%s).$$"
    printf '\n# clawd — Claude Code state mascot (https://github.com/oauramos/sketchybar-clawd)\n%s\n' "$SOURCE_LINE" >>"$RC"
    say "  added (backup written alongside)."
  else
    say "  skipped. Add this near the end of $RC yourself:"
    say "      $SOURCE_LINE"
  fi
else
  # missing, or a read-only/store symlink (Nix/home-manager, etc.)
  warn "$RC is missing or not writable — add this line near the end of it yourself:"
  say  "      $SOURCE_LINE"
fi
say ""

# --- 4. Claude Code hooks ----------------------------------------------------
step "Claude Code hooks"
install_hooks=0
case "$HOOKS_MODE" in
  yes) install_hooks=1 ;;
  no)  say "  skipped (--no-hooks)." ;;
  ask)
    if [ "$PRINT_ONLY" = "1" ]; then
      say "  would offer to merge hooks into ~/.claude/settings.json via hooks/install-hooks.sh"
    elif confirm "  Install the Claude Code hooks (merge into ~/.claude/settings.json)?"; then
      install_hooks=1
    else
      say "  skipped. Run later: hooks/install-hooks.sh --hook \"$DEST/clawd.hook.sh\""
    fi
    ;;
esac
if [ "$install_hooks" = "1" ] && [ "$PRINT_ONLY" != "1" ]; then
  if command -v jq >/dev/null 2>&1; then
    CONFIG_DIR="$CONFIG_DIR" bash "$SELF/hooks/install-hooks.sh" --hook "$DEST/clawd.hook.sh"
  else
    warn "jq not found — skipping hooks. Install jq, then run:"
    say  "      hooks/install-hooks.sh --hook \"$DEST/clawd.hook.sh\""
  fi
fi
say ""

# --- 5. reload ---------------------------------------------------------------
if [ -n "$SB" ] && [ "$PRINT_ONLY" != "1" ]; then
  if confirm "Reload SketchyBar now?"; then
    "$SB" --reload && say "✓ reloaded."
  else
    say "Run 'sketchybar --reload' when ready."
  fi
fi

say ""
step "Done."
say "Manual state test:  sketchybar --trigger claude_state STATE=working   (then =waiting / =idle)"
say "How many clawds:    sketchybar-clawd 12   (then: sketchybar-clawd reset)"
