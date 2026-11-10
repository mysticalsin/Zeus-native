#!/usr/bin/env bash
# Builds the benchmark clips with macOS voices: 16 kHz mono WAV plus the exact reference text.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p clips
: > clips/refs.tsv
i=0
while IFS='|' read -r voice text; do
  [[ -z "$voice" ]] && continue
  i=$((i+1)); name=$(printf "clip%02d" "$i")
  say -v "$voice" -o "clips/$name.wav" --data-format=LEI16@16000 --channels=1 "$text"
  printf "%s\t%s\t%s\n" "$name" "$voice" "$text" >> clips/refs.tsv
done < sentences.txt
echo "made $i clips"
