#!/usr/bin/env bash
# Local trusted-Mac run of the SwiftUI accessibility journey (ScribeTrustedAccessibilityJourneyTests).
# Run it from a terminal that already has Accessibility trust. It never requests permissions, never
# scripts other apps, never captures screen or audio, and the test only touches its own windows.
# Not part of CI or the closed-loop full gate; full gate mode consumes its receipt via run.py --trusted-receipt.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "trusted-ax-journey: macOS only" >&2; exit 2
fi
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "trusted-ax-journey: refuses to run in CI" >&2; exit 2
fi

BUILD_DIR="$HOME/AI-Brain-build/zeus-native-build"
swift build --build-tests --scratch-path "$BUILD_DIR"
exec python3 qa/closed-loop/trusted_ax.py --build-dir "$BUILD_DIR"
