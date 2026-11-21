#!/bin/sh
# Red repro on codex/integration-20261111. TabHoldGate is implemented and tested,
# and Sources/Zeus has no caller. Exits 1 while the app still ignores it.
set -eu
cd "$(CDPATH= cd -P "$(dirname "$0")/../.." && pwd)"
hits=$(git grep -n "TabHoldGate" HEAD -- Sources/Zeus || true)
printf '%s\n' "$hits"
if printf '%s\n' "$hits" | grep -q .; then
    echo "TabHoldGate is now referenced from the app"
    exit 0
fi
echo "BUG: TabHoldGate has no caller under Sources/Zeus"
exit 1
