#!/usr/bin/env bash
# Renders the welcome guide's films (Sources/Zeus/Onboarding/OnboardingFilms.swift and
# OnboardingFilmScenes.swift) to H.264, offline, from the SwiftUI scenes and the v2 mascot sprites:
#   intro 1040x798 30 fps 20.0 s, learn-running 720x900 60 fps 7.0 s, learn-murmure 720x1280 30 fps 25.1 s,
#   learn-approve 5.0 s, learn-previews 10.0 s, learn-shortcuts 7.0 s, learn-everywhere 8.5 s (720x900, 30 fps).
# Needs ffmpeg. Run after `swift build -c release` (or debug); writes Sources/Zeus/Onboarding/Media/Films/*.mp4.
# Usage: scripts/render-onboarding-films.sh [film ...]   (names: intro running murmure approve previews shortcuts everywhere)
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(swift build ${CONFIG:+-c $CONFIG} --show-bin-path)/Zeus"
OUT=Sources/Zeus/Onboarding/Media/Films
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
FILMS=("$@")
[[ ${#FILMS[@]} -gt 0 ]] || FILMS=(intro running murmure approve previews shortcuts everywhere)
for name in "${FILMS[@]}"; do
  case "$name" in
    running) fps=60; file=learn-running ;;
    intro) fps=30; file=intro ;;
    *) fps=30; file="learn-$name" ;;
  esac
  "$BIN" --render-film "$name" "$TMP/$name"
  ffmpeg -v error -y -framerate "$fps" -i "$TMP/$name/frame-%05d.png" -c:v libx264 -preset slow -crf "${CRF:-23}" \
    -pix_fmt yuv420p -movflags +faststart -an "$OUT/$file.mp4"
  ffprobe -v error -show_entries stream=width,height,r_frame_rate:format=duration -of compact "$OUT/$file.mp4"
  rm -rf "$TMP/$name"
done
ls -l "$OUT"
