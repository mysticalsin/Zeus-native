#!/usr/bin/env bash
# Checks the Developer ID, secure timestamp and hardened runtime on the app and every helper.
set -euo pipefail
APP="${1:?Usage: scripts/verify-release-signature.sh path/to/Zeus.app}"
codesign --verify --deep --strict "$APP"
for binary in "$APP" "$APP"/Contents/Helpers/*; do
  [ -e "$binary" ] || continue
  details="$(codesign --display --verbose=4 "$binary" 2>&1)"
  if ! grep -q '^Authority=Developer ID Application:' <<<"$details" \
    || ! grep -Eq '^TeamIdentifier=[A-Z0-9]+$' <<<"$details" \
    || ! grep -q '^Timestamp=' <<<"$details" \
    || grep -Eq '^Timestamp=(none|invalid)$' <<<"$details" \
    || ! grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$details"; then
    echo "Release signature rejected: $binary needs Developer ID, a secure timestamp and hardened runtime." >&2
    exit 1
  fi
done
