#!/bin/bash
# Render the fixed script set with the Mac-only voices.
# Every file this script creates is under the output directory it is given.
# Usage: qa/voice/mac/render_mac.sh OUTPUT_DIR

set -euo pipefail

if [[ $# -ne 1 || -z ${1} ]]; then
  echo "usage: render_mac.sh OUTPUT_DIR" >&2
  exit 2
fi

mkdir -p "$1"
out=$(cd "$1" && pwd -P)
here=$(cd "$(dirname "$0")" && pwd -P)
scripts=$(cd "$here/../scripts" && pwd -P)

confine() {
  local target=$1
  local parent
  parent=$(cd "$(dirname "$target")" && pwd -P)
  case "$parent" in
    "$out"|"$out"/*) ;;
    *)
      echo "refusing to write outside $out: $target" >&2
      exit 3
      ;;
  esac
}

write_status() {
  local path=$1
  shift
  confine "$path"
  printf '%s\n' "$@" > "$path"
}

if [[ $(uname -s) != Darwin ]]; then
  write_status "$out/host-status.txt" \
    "host: $(uname -s)" \
    "avspeech: not run" \
    "say: not run" \
    "zeus.synthetic: not run" \
    "reason: AVSpeechSynthesizer and say exist only on macOS. No audio was written."
  echo "render_mac.sh: not macOS, no audio written" >&2
  exit 2
fi

spoken_text() {
  local source=$1
  local dest=$2
  python3 - "$source" "$dest" <<'PY'
import pathlib, sys
source, dest = sys.argv[1:]
text = pathlib.Path(source).read_text(encoding="utf-8")
marker = "[[BARGE-IN]]"
index = text.find(marker)
if index >= 0:
    text = text[:index] + " " + text[index + len(marker):]
pathlib.Path(dest).write_text(" ".join(text.split()) + "\n", encoding="utf-8")
PY
}

render_say() {
  local name=$1
  local textfile=$2
  local dir=$out/say
  mkdir -p "$dir"
  local aiff=$dir/$name.aiff
  local wav=$dir/$name.wav
  confine "$aiff"
  confine "$wav"
  local voice_args=()
  if [[ -n ${SAY_VOICE:-} ]]; then
    voice_args=(-v "$SAY_VOICE")
  fi
  local started ended
  started=$(python3 -c 'import time; print(f"{time.perf_counter():.6f}")')
  say "${voice_args[@]}" -f "$textfile" -o "$aiff"
  afconvert -f WAVE -d LEI16 "$aiff" "$wav"
  rm -f "$aiff"
  ended=$(python3 -c 'import time; print(f"{time.perf_counter():.6f}")')
  python3 - "$dir/$name.timing.json" "$name" "$textfile" "$started" "$ended" <<'PY'
import json, pathlib, sys
path, name, textfile, started, ended = sys.argv[1:]
text = pathlib.Path(textfile).read_text(encoding="utf-8").strip()
payload = {
    "provider": "say",
    "script": name,
    "text": text,
    "request_start_s": 0.0,
    "wav_origin_s": 0.0,
    "first_audio_s": float(ended) - float(started),
    "ttfa_note": "Wall clock of say plus afconvert. say does not use Zeus's Ultron effect.",
}
pathlib.Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

render_swift() {
  local name=$1
  local textfile=$2
  local dir=$out/avspeech
  mkdir -p "$dir"
  local wav=$dir/$name.wav
  confine "$wav"
  local started ended
  started=$(python3 -c 'import time; print(f"{time.perf_counter():.6f}")')
  swift "$here/render_avspeech.swift" "$wav" "$textfile"
  ended=$(python3 -c 'import time; print(f"{time.perf_counter():.6f}")')
  python3 - "$dir/$name.timing.json" "$name" "$textfile" "$started" "$ended" <<'PY'
import json, pathlib, sys
path, name, textfile, started, ended = sys.argv[1:]
text = pathlib.Path(textfile).read_text(encoding="utf-8").strip()
payload = {
    "provider": "avspeech",
    "script": name,
    "text": text,
    "request_start_s": 0.0,
    "wav_origin_s": 0.0,
    "first_audio_s": float(ended) - float(started),
    "rate": "AVSpeechUtteranceDefaultSpeechRate * 0.92",
    "pitch_multiplier": 0.82,
    "ttfa_note": "Wall clock of AVSpeechSynthesizer.write. The Ultron effect chain is not in this process.",
}
pathlib.Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

mkdir -p "$out/spoken" "$out/zeus-synthetic"
for script in "$scripts"/*.txt; do
  name=$(basename "$script" .txt)
  spoken=$out/spoken/$name.txt
  confine "$spoken"
  spoken_text "$script" "$spoken"
  render_say "$name" "$spoken"
  if command -v swift >/dev/null 2>&1; then
    render_swift "$name" "$spoken"
  fi
done

write_status "$out/zeus-synthetic/STATUS.txt" \
  "voice id: zeus.synthetic" \
  "reachable headlessly: no" \
  "ZEUS_BIN: ${ZEUS_BIN:-unset}" \
  "The id is PersonaSyntheticVoice.voiceID on commit 665b9167303f9596d5222b77a663e36f780d60d7 (PR 52). PersonaVoiceResolver always returns it. Speaker does not read it, and no Zeus flag renders these scripts to a WAV." \
  "Zeus --voice-engine-selftest speaks one fixed line through whatever engines are configured and writes a receipt. Its default receipt directory is outside this output dir, and the line is not this script set. This script does not launch that command." \
  "No audio was invented for zeus.synthetic."

echo "render_mac.sh: wrote under $out"
