#!/usr/bin/env bash
#
# Symlink this plugin into ~/.hermes/plugins/agenthub and enable it.
# Idempotent — safe to re-run after `git pull`.
#
# Usage:
#   bash plugin/install.sh           # install
#   bash plugin/install.sh uninstall # remove the symlink + disable
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$HERE/agenthub"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
TARGET="$HERMES_HOME/plugins/agenthub"

action="${1:-install}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: $1 not found in PATH" >&2
    exit 1
  }
}

case "$action" in
  install)
    require hermes
    [ -d "$SOURCE_DIR" ] || {
      echo "error: $SOURCE_DIR does not exist" >&2
      exit 1
    }
    mkdir -p "$HERMES_HOME/plugins"
    if [ -L "$TARGET" ]; then
      current="$(readlink "$TARGET")"
      if [ "$current" = "$SOURCE_DIR" ]; then
        echo "agenthub plugin already linked at $TARGET"
      else
        echo "agenthub plugin link points elsewhere ($current); replacing"
        rm "$TARGET"
        ln -s "$SOURCE_DIR" "$TARGET"
      fi
    elif [ -e "$TARGET" ]; then
      echo "error: $TARGET exists and is not a symlink — refusing to overwrite" >&2
      exit 1
    else
      ln -s "$SOURCE_DIR" "$TARGET"
      echo "linked $TARGET -> $SOURCE_DIR"
    fi
    hermes plugins enable agenthub
    echo
    echo "Done. Restart your long-running hermes process (gateway / acp) so the plugin loads."
    echo "On startup it prints a QR code to stderr; scan it with the AgentHub mobile App."
    ;;
  uninstall)
    if [ -L "$TARGET" ]; then
      rm "$TARGET"
      echo "removed $TARGET"
    fi
    require hermes
    hermes plugins disable agenthub || true
    ;;
  *)
    echo "usage: $0 [install|uninstall]" >&2
    exit 64
    ;;
esac
