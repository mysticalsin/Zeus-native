#!/bin/bash
# Measures Zeus voice latency from the real app. Run it, then hold the talk key and ask something.
#
#   bash scripts/voice-latency.sh              watch live: one table row per turn, p50/p90 when you press Ctrl-C
#   bash scripts/voice-latency.sh --replay     analyse the turns already in the log, then exit
#   bash scripts/voice-latency.sh --replay --last 20
#   bash scripts/voice-latency.sh --file PATH  analyse another log file (no running Zeus needed)
#
# It launches nothing. If Zeus is not running it says how to start it and exits 3.
# Reads ~/Library/Logs/Zeus/voice.log (override with ZEUS_LOG_DIR). The `voice-latency` lines hold stage times
# in ms since key-up, engine names and a short reason: no transcript, no answer text, no key.
# Stages: key_up(0) transcript request first_token first_sentence tts_request first_audio turn_end.
# The headline is ttfa = key-up -> first audio. Targets (docs/VOICE-LATENCY.md): 1200 ms with an API key and
# a cloud voice, 2500 ms CLI-only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${ZEUS_LOG_DIR:-$HOME/Library/Logs/Zeus}"
LOG="$LOG_DIR/voice.log"
MODE="live"
LAST=""
FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --replay) MODE="replay" ;;
        --last) shift; LAST="${1:-}" ;;
        --file) shift; FILE="${1:-}"; MODE="file" ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "unknown option $1" >&2; exit 64 ;;
    esac
    shift
done

PY=(python3 -I "$HERE/voice-latency.py")
EXTRA=()
if [ -n "$LAST" ]; then EXTRA=(--last "$LAST"); fi

if [ "$MODE" = "file" ]; then
    exec "${PY[@]}" --file "$FILE" ${EXTRA[@]+"${EXTRA[@]}"}
fi

if ! pgrep -x Zeus >/dev/null 2>&1; then
    cat >&2 <<'MSG'
Zeus is not running, so there is nothing to measure. This script starts nothing.
Start Zeus yourself, for example:   open -a Zeus
then run this script again, hold the talk key, and ask a question.
To analyse turns from an earlier session instead:   bash scripts/voice-latency.sh --replay
MSG
    [ "$MODE" = "replay" ] || exit 3
fi

if [ ! -f "$LOG" ]; then
    echo "No voice log yet at $LOG. Talk to Zeus once, then run this again." >&2
    [ "$MODE" = "replay" ] && exit 4
    : >/dev/null
fi

if [ "$MODE" = "replay" ]; then
    exec "${PY[@]}" --file "$LOG" ${EXTRA[@]+"${EXTRA[@]}"}
fi

echo "Watching $LOG. Hold the talk key and ask Zeus something. Ctrl-C prints p50 and p90."
# tail -F follows the log through rotation; only new lines are read.
tail -n 0 -F "$LOG" 2>/dev/null | "${PY[@]}" --live
