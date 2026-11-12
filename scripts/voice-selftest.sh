#!/bin/bash
# Owner-run voice self-test. Starts a built Zeus.app with --voice-engine-selftest: one fixed line through each
# available engine (ElevenLabs, OpenAI, Kokoro, Mac voice) with the Ultron effect, then validates the receipt it
# writes to ~/AI-Brain-build/voice-selftest/. It refuses to run in CI and never reads or prints a key.
#
#   bash scripts/voice-selftest.sh [--silent] [<path to Zeus.app>] [--receipt <absolute path>]
#
# Default app: the latest ~/AI-Brain-build/zeus-qa-*/app*/Zeus.app. --silent runs the chain at zero volume.
# Exit: 0 the Mac voice spoke through the effect and was not Samantha; 1 otherwise.
set -euo pipefail
umask 077

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "voice-selftest: refusing to run in CI. It plays audio and needs a logged-in Mac." >&2
    exit 78
fi

APP=""
SILENT=""
RECEIPT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --silent) SILENT="--silent" ;;
        --receipt) shift; RECEIPT="${1:-}" ;;
        -*) echo "unknown option $1" >&2; exit 64 ;;
        *) APP="$1" ;;
    esac
    shift
done

if [ -z "$APP" ]; then
    # shellcheck disable=SC2012
    APP="$(ls -dt "$HOME"/AI-Brain-build/zeus-qa-*/app*/Zeus.app 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$APP" ] || [ ! -x "$APP/Contents/MacOS/Zeus" ]; then
    echo "voice-selftest: no Zeus.app found. Pass the path to a built app." >&2
    exit 64
fi
DIR="$HOME/AI-Brain-build/voice-selftest"
mkdir -p "$DIR"
if [ -z "$RECEIPT" ]; then
    RECEIPT="$DIR/receipt-$(date +%Y%m%d-%H%M%S).json"
fi
case "$RECEIPT" in /*) ;; *) echo "receipt path must be absolute" >&2; exit 64 ;; esac

echo "app:     $APP"
echo "receipt: $RECEIPT"
rm -f "$RECEIPT"
set +e
"$APP/Contents/MacOS/Zeus" --voice-engine-selftest --receipt "$RECEIPT" $SILENT &
PID=$!
# Each engine is bounded at 25 s; this only guards against a process that ignores that.
( sleep 150; kill -9 "$PID" 2>/dev/null ) &
GUARD=$!
wait "$PID"
RC=$?
kill "$GUARD" 2>/dev/null
wait "$GUARD" 2>/dev/null
set -e

if [ ! -f "$RECEIPT" ]; then
    echo "voice-selftest: the app wrote no receipt (exit $RC)." >&2
    exit 1
fi
python3 -I - "$RECEIPT" "$RC" <<'PY'
import json, sys
receipt = json.load(open(sys.argv[1]))
rows = receipt["rows"]
print("system voice:", receipt["systemVoice"])
for row in rows:
    status = "spoke" if row["spoke"] else ("FAILED" if row["available"] else "skipped")
    ms = row["firstAudioMs"]
    print(f'  {row["engine"]:<11} {status:<8} first audio {ms if ms is not None else "-"} ms  effect {row["effectPercent"]}%  {row["reason"]}')
ok = any(r["engine"] == "system" and r["spoke"] for r in rows) and "samantha" not in receipt["systemVoice"].lower()
print("PASS" if ok else "FAIL")
sys.exit(0 if ok and sys.argv[2] == "0" else 1)
PY
