#!/usr/bin/env bash
# manual-run harness. Build Zeus at ~/Desktop/Zeus-latest-<sha8>.app.
# It does not open Zeus and it never launches /Applications/Zeus.app.
# A failed run writes a receipt marked FAIL.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
# A Mac CI job must not build onto the Desktop. Linux still records every
# hands-on journey as unproven and does not build.
if [ "$(uname -s)" = "Darwin" ]; then
  ci_name=GITHUB_ACTIONS
  if [ -n "${!ci_name:-}" ] || [ -n "${CI:-}" ]; then
    echo "qa-native-run: refusing to build in CI." >&2
    exit 2
  fi
fi
exec python3 -I "$repo/qa/native-qa/harness.py" --repo "$repo" "$@"
