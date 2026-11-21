#!/bin/sh
# Red repro for PR #42 (08e09710f41b). The gesture router defines click, double
# click, triple click, hold and right-swipe, but the only production call site
# sends a trackpad sample. Exits 1 while that remains true.
set -eu
cd "$(CDPATH= cd -P "$(dirname "$0")/../.." && pwd)"
SHA=08e09710f41b
git cat-file -e "$SHA^{commit}" || { echo "missing commit $SHA (fetch zeus-bot/settings-weather)" >&2; exit 2; }
hits=$(git grep -n "TopBarPointerSample" "$SHA" -- 'Sources/Zeus' 'Sources/ZeusCore' || true)
printf '%s\n' "$hits"
printf '%s\n' "$hits" | grep -q 'TopBarPointerSample(\.down' && { echo "a click sample is now wired"; exit 0; }
printf '%s\n' "$hits" | grep -q 'TopBarPointerSample(\.hold' && { echo "a hold sample is now wired"; exit 0; }
printf '%s\n' "$hits" | grep -q 'TopBarPointerSample(\.swipeRight' && { echo "a right-swipe sample is now wired"; exit 0; }
echo "BUG: production sources never send click, hold, or right-swipe samples"
exit 1
