#!/usr/bin/env bash
# Build Zeus at ~/Desktop/Zeus-latest-<sha8>.app and write an empty hands-on receipt.
# A later Mac run fills each screenshot and result slot. This script does not install the app.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
  echo "qa-native-run: refusing to run in CI." >&2
  exit 2
fi
exec python3 -I "$repo/qa/native-qa/harness.py" --repo "$repo" "$@"
