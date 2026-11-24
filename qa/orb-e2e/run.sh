#!/bin/sh
# Deep orb end-to-end suite. Fakes only. One command from the clone root:
#   qa/orb-e2e/run.sh
#   python3 qa/orb-e2e/test_runner.py
# Output directory: $ZEUS_E2E_OUT, or $TMPDIR/zeus-e2e/orb/<sha8>/
# Writes summary.json, junit.xml, and per-state PNGs.
set -eu
cd "$(dirname "$0")/../.."
if ! command -v swiftc >/dev/null 2>&1; then
  if [ -x "$HOME/swift/usr/bin/swiftc" ]; then
    PATH="$HOME/swift/usr/bin:$PATH"
    export PATH
  fi
fi
python3 qa/orb-e2e/test_runner.py
python3 qa/orb-e2e/runner.py
