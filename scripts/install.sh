#!/usr/bin/env bash
# Installs a prepared app only after making and checking a rollback copy. Does not build or launch it.
# Usage: scripts/install.sh [build/Zeus.app] [/Applications/Zeus.app]
# Set ZEUS_ROLLBACK_DIR to choose a different backup folder. Never deletes prior rollback copies.
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${1:-build/Zeus.app}"
DESTINATION="${2:-/Applications/Zeus.app}"
ROLLBACK_ROOT="${ZEUS_ROLLBACK_DIR:-$HOME/Library/Application Support/Zeus/Rollbacks}"

if [ ! -d "$SOURCE" ] || [ -L "$SOURCE" ] || [ ! -x "$SOURCE/Contents/MacOS/Zeus" ]; then
  echo "Choose an existing Zeus.app bundle to install." >&2; exit 1
fi
if [ -L "$DESTINATION" ] || { [ -e "$DESTINATION" ] && [ ! -d "$DESTINATION" ]; }; then
  echo "The install destination must be an app folder, not a symlink or file." >&2; exit 1
fi
SOURCE="$(cd "$SOURCE" && pwd -P)"
DEST_PARENT="$(cd "$(dirname "$DESTINATION")" && pwd -P)"
DESTINATION="$DEST_PARENT/$(basename "$DESTINATION")"
if [ "$SOURCE" = "$DESTINATION" ] || [ "$(basename "$DESTINATION")" != Zeus.app ]; then
  echo "Choose a different destination named Zeus.app." >&2; exit 1
fi
if pgrep -x Zeus >/dev/null; then
  echo "Quit Zeus before installing. The installed copy has not been changed." >&2; exit 1
fi
codesign --verify --deep --strict "$SOURCE"

STAGE="$(mktemp -d "$DEST_PARENT/.zeus-install.XXXXXX")"
OLD_MOVED=0
NEW_INSTALLED=0
cleanup() {
  local result=$?
  if [ "$OLD_MOVED" = 1 ] && [ "$NEW_INSTALLED" = 0 ]; then
    if [ ! -e "$DESTINATION" ]; then
      mv "$STAGE/previous.app" "$DESTINATION" || {
        echo "Automatic restore failed. The previous app remains at $STAGE/previous.app." >&2
        return 1
      }
    else
      echo "The destination changed during install. The previous app remains at $STAGE/previous.app." >&2
      return 1
    fi
  fi
  rm -rf "$STAGE"
  return "$result"
}
trap cleanup EXIT
ditto "$SOURCE" "$STAGE/Zeus.app"
codesign --verify --deep --strict "$STAGE/Zeus.app"

if [ -d "$DESTINATION" ]; then
  mkdir -p "$ROLLBACK_ROOT"
  chmod 700 "$ROLLBACK_ROOT"
  BACKUP="$(mktemp -d "$ROLLBACK_ROOT/$(date +%Y%m%d-%H%M%S).XXXXXX")/Zeus.app"
  ditto "$DESTINATION" "$BACKUP"
  diff -qr "$DESTINATION" "$BACKUP" >/dev/null
  echo "Rollback copy verified: $BACKUP"
  mv "$DESTINATION" "$STAGE/previous.app"
  OLD_MOVED=1
fi
mv "$STAGE/Zeus.app" "$DESTINATION"
NEW_INSTALLED=1
echo "Installed $DESTINATION. Launch it yourself to answer any macOS permission prompts."
