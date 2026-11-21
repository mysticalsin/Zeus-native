#!/usr/bin/env bash
# manual-run harness. Build Zeus at ~/Desktop/Zeus-latest-<sha8>.app.
# It does not open Zeus and it never launches /Applications/Zeus.app.
# A failed run writes a receipt marked FAIL.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
  echo "qa-native-run: refusing to run in CI." >&2
  exit 2
fi
exec python3 -I "$repo/qa/native-qa/harness.py" --repo "$repo" "$@"
