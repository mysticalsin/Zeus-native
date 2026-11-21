#!/bin/bash
# Owner-run pointing self-test. Starts a built Zeus.app with --pointing-selftest, waits for it,
# and validates the receipt it wrote. It refuses to run in CI and never grants or scripts a permission:
# a missing Screen Recording or Accessibility grant shows up as a "blocked" row with the exact pane.
#
#   bash scripts/pointing-selftest.sh [<path to Zeus.app>] [--live] [--receipt <absolute path>]
#
# Default app: ZEUS_APP, else build/Zeus.app, else the newest ~/Desktop/Zeus-latest-*.app.
# Exit: 0 every required check passed; 3 valid with permission blocks; anything else is a failure.
set -euo pipefail
umask 077

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "pointing-selftest: refusing to run in CI. It opens windows and needs a logged-in Mac." >&2
    exit 78
fi

APP=""
LIVE=""
RECEIPT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --live) LIVE="--live" ;;
        --receipt) shift; RECEIPT="${1:-}" ;;
        -*) echo "unknown option $1" >&2; exit 64 ;;
        *) APP="$1" ;;
    esac
    shift
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$APP" ]; then
    if [ -n "${ZEUS_APP:-}" ]; then
        APP="$ZEUS_APP"
    elif [ -x "$ROOT/build/Zeus.app/Contents/MacOS/Zeus" ]; then
        APP="$ROOT/build/Zeus.app"
    else
        # shellcheck disable=SC2012
        APP="$(ls -dt "$HOME"/Desktop/Zeus-latest-*.app 2>/dev/null | head -n 1 || true)"
    fi
fi
if [ -z "$APP" ] || [ ! -x "$APP/Contents/MacOS/Zeus" ]; then
    echo "pointing-selftest: no Zeus.app found. Pass the path to a built app." >&2
    exit 64
fi
if [ -z "$RECEIPT" ]; then
    RECEIPT="${TMPDIR:-/tmp}/zeus-pointing-receipt-$(date +%Y%m%d-%H%M%S).json"
fi
case "$RECEIPT" in /*) ;; *) echo "receipt path must be absolute" >&2; exit 64 ;; esac

SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "app:     $APP"
echo "receipt: $RECEIPT"
echo "mode:    ${LIVE:-deterministic}   (git $SHA)"

rm -f "$RECEIPT"
set +e
ZEUS_GIT_SHA="$SHA" "$APP/Contents/MacOS/Zeus" --pointing-selftest --receipt "$RECEIPT" $LIVE &
PID=$!
# The app has its own 120 s watchdog; this one only guards against a process that ignores it.
( sleep 135; kill -9 "$PID" 2>/dev/null ) &
GUARD=$!
wait "$PID"
RC=$?
kill "$GUARD" 2>/dev/null
wait "$GUARD" 2>/dev/null
set -e

if [ ! -f "$RECEIPT" ]; then
    echo "pointing-selftest: the app wrote no receipt (exit $RC)." >&2
    exit 1
fi
python3 -I "$ROOT/qa/closed-loop/pointing_receipt.py" "$RECEIPT" --rc "$RC"
