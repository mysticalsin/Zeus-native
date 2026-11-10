#!/bin/bash
# N5/N6 silent E2E hooks for the integrator (requires running Zeus via zeus CLI, not Zeus.app direct).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QA="$ROOT/../glance-clone-proof/qa/N"
mkdir -p "$QA/N6" "$QA"
LOG="$QA/n5-screen-share.log"
exec > >(tee "$LOG") 2>&1

echo "=== N5 screen share ==="
zeus debug screen-share off
zeus debug screen-share state
zeus debug screen-share on
zeus debug screen-share state
screencapture -x "$QA/n5-share-on.png"
zeus debug screen-share off
screencapture -x "$QA/n5-share-off.png"
echo "screenshots: $QA/n5-share-on.png $QA/n5-share-off.png"

echo "=== N6 update badge ==="
zeus debug update fake 9.9.0
zeus debug open-settings general
sleep 1
screencapture -x "$QA/N6/settings-1080p.png"
zeus debug update dismiss
zeus debug update fake 9.9.1
zeus debug update state 2>/dev/null || true
echo "proof under $QA and $QA/N6"
