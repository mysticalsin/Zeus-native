#!/bin/sh
# Speech-to-text stage times for the talk hold and the Murmur tap.
#
# Run this on a Mac, from a detached clone, after PR #98 has merged.
# Until then the packaged app does not build, and this script says so.
# It never opens the live microphone and it never uses a recording of a person.
# The spoken clip is the Mac's own speech synthesizer.
#
# Usage:
#   bash scripts/stt-latency-mac.sh
#   bash scripts/stt-latency-mac.sh /path/to/Zeus.app
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CLONE=${STT_CLONE:-$(mktemp -d /tmp/zeus-stt-measure.XXXXXX)}
ARCH=${STT_ARCH:-arm64}

echo "stt-latency clone: $CLONE"
if [ "$CLONE" != "$ROOT" ]; then
  git clone --local "$ROOT" "$CLONE" >/dev/null
  git -C "$CLONE" checkout --detach HEAD >/dev/null
fi
cd "$CLONE"

echo
echo "== injected clock, both paths, before and after =="
echo "key_down is 0. capture / vad / asr / delivery follow."
echo "BEFORE is the previous wait (2.5 s final, task left running, 30 s batch give-up)."
echo "AFTER is the on-device budget in this build."
swift build --product zeus-cli --arch "$ARCH" -c release
CLI=$CLONE/.build/$ARCH-apple-macosx/release/zeus-cli
if [ ! -x "$CLI" ]; then CLI=$CLONE/.build/release/zeus-cli; fi
"$CLI" stt-latency

APP=${1:-}
if [ -z "$APP" ]; then
  echo
  echo "== packaged build =="
  echo "PR #98 is required before integration builds. Trying once."
  if ! swift build --product Zeus --arch "$ARCH" -c release; then
    echo "PACKAGED_BUILD blocked: integration does not build until PR #98 merges."
    echo "The injected-clock report above is the before/after this host can print today."
    exit 2
  fi
  APP="$CLONE/.build/$ARCH-apple-macosx/release/Zeus"
fi

WAV=$CLONE/stt-synthetic.wav
rm -f "$WAV"
# System synthesizer only. No microphone and no recording of a real voice.
say -o "$WAV" --data-format=LEI16@16000 "The latency budget is under half a second."
echo
echo "== file-fed synthetic utterance =="
echo "wav: $WAV"
LOG=${ZEUS_LOG_DIR:-$HOME/Library/Logs/Zeus}
BEFORE_LOG=$CLONE/stt-before.log
if [ -f "$LOG/voice.log" ]; then
  cp "$LOG/voice.log" "$BEFORE_LOG"
else
  : > "$BEFORE_LOG"
fi
# dictate-file is the Murmur recognizer fed from a file. Key down and key up are the
# injected-clock events printed above; this process does not post a real key event.
"$APP" debug dictate-file "$WAV" || true
echo "-- packaged stages (lines added by this run) --"
if [ -f "$LOG/voice.log" ]; then
  comm -13 "$BEFORE_LOG" "$LOG/voice.log" | grep -E 'stt-latency|stt-failure' || echo "(no stt-latency line yet)"
else
  echo "(no voice log)"
fi
