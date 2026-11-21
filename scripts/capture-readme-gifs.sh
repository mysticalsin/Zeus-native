#!/usr/bin/env bash
# Opt-in captures for the five README GIFs.
#
# macOS only. Without --record this script prints the shot list and writes nothing.
# It never launches, installs, replaces, or signals an application. It never calls
# defaults, osascript, or anything else that would read or write system settings
# or the Keychain. Output stays under docs/media/, and only for the five shot ids.
#
#   scripts/capture-readme-gifs.sh
#   scripts/capture-readme-gifs.sh --record idle-top-bar --region X,Y,W,H
#
# See docs/media/README.md.

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
media_link="$repo/docs/media"
die() { printf 'capture-readme-gifs: %s\n' "$1" >&2; exit "${2:-2}"; }

if [ ! -d "$media_link" ] || [ -L "$media_link" ]; then
  die "docs/media must be a real directory inside this repository."
fi
media="$(cd "$media_link" && pwd -P)"
case "$media" in
  "$repo"/docs/media) ;;
  *) die "docs/media resolved outside the repository. Refusing to write." ;;
esac

print_shots() {
  cat <<'EOF'
Shots this script can write, and only these:

  idle-top-bar
    docs/media/idle-top-bar.gif
    Idle top bar. The closed notch, or the pill on a Mac without one.
    Do not expand the panel.

  expanded-panel
    docs/media/expanded-panel.gif
    Expanded top bar. The open panel, with the tab row and one page.

  murmur-dictation
    docs/media/murmur-dictation.gif
    Murmure dictation. Hold Right Command, the default dictation key.
    Show the live words and the orb. Focus a scratch document first.

  voice-orb
    docs/media/voice-orb.gif
    Voice orb while a talk turn is listening or speaking.
    Right Option is the default second talk key. Hold it a quarter second.

  settings
    docs/media/settings.gif
    Settings window, on Voice or Murmure.

Arrange the running app yourself. This script does not open it.
Pass --region X,Y,W,H using the coordinates screencapture -R expects.
ffmpeg, if it is on PATH, assembles the GIF. Nothing is installed.
EOF
}

usage() {
  cat <<'EOF'
Usage:
  scripts/capture-readme-gifs.sh [--help]
  scripts/capture-readme-gifs.sh --record SHOT --region X,Y,W,H [--duration N] [--fps N] [--yes] [--replace]

SHOT is one of: idle-top-bar, expanded-panel, murmur-dictation, voice-orb, settings.

--record is the opt-in. It runs only on macOS, and it refuses CI.
Without --record the script prints the shot list and exits.
EOF
  printf '\n'
  print_shots
}

shot_file() {
  case "$1" in
    idle-top-bar) printf '%s\n' idle-top-bar.gif ;;
    expanded-panel) printf '%s\n' expanded-panel.gif ;;
    murmur-dictation) printf '%s\n' murmur-dictation.gif ;;
    voice-orb) printf '%s\n' voice-orb.gif ;;
    settings) printf '%s\n' settings.gif ;;
    *) return 1 ;;
  esac
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
}

is_int() {
  local body="$1"
  case "$body" in
    -) return 1 ;;
    -*) body="${body#-}" ;;
  esac
  case "$body" in
    ''|*[!0-9]*) return 1 ;;
  esac
}

record=0
yes=0
replace=0
shot=""
region=""
duration=4
fps=8

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --record)
      record=1
      shift
      [ "$#" -ge 1 ] || die "--record needs a shot id."
      shot="$1"
      ;;
    --region)
      shift
      [ "$#" -ge 1 ] || die "--region needs X,Y,W,H."
      region="$1"
      ;;
    --duration)
      shift
      [ "$#" -ge 1 ] || die "--duration needs a number of seconds."
      duration="$1"
      ;;
    --fps)
      shift
      [ "$#" -ge 1 ] || die "--fps needs a number."
      fps="$1"
      ;;
    --yes) yes=1 ;;
    --replace) replace=1 ;;
    --list)
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

if [ "$record" -eq 0 ]; then
  print_shots
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || die "macOS only. No capture was started and nothing was written."
[ -z "${CI:-}${GITHUB_ACTIONS:-}" ] || die "Refusing to capture in CI."

file="$(shot_file "$shot")" || die "Unknown shot: $shot"
dest="$media/$file"
frames="$media/${shot}-frames"
work="$media/.capture-work/$shot"

case "$dest" in
  "$media"/*.gif) ;;
  *) die "Refusing to write outside docs/media." ;;
esac
case "$file" in
  */*|.|..) die "Refusing shot file name: $file" ;;
esac

commas="${region//[^,]/}"
[ "${#commas}" -eq 3 ] || die "--region must be X,Y,W,H."
IFS=, read -r rx ry rw rh <<<"$region"
is_int "$rx" && is_int "$ry" && is_uint "$rw" && is_uint "$rh" || die "--region values must be integers."
[ "$rw" -ge 1 ] && [ "$rw" -le 10000 ] || die "Region width must be from 1 to 10000."
[ "$rh" -ge 1 ] && [ "$rh" -le 10000 ] || die "Region height must be from 1 to 10000."
is_uint "$duration" || die "--duration must be a whole number of seconds."
is_uint "$fps" || die "--fps must be a whole number."
[ "$duration" -ge 1 ] && [ "$duration" -le 12 ] || die "--duration must be from 1 to 12 seconds."
[ "$fps" -ge 4 ] && [ "$fps" -le 12 ] || die "--fps must be from 4 to 12."

capture="/usr/sbin/screencapture"
[ -x "$capture" ] || die "screencapture is not at /usr/sbin/screencapture."

if [ -L "$dest" ] || [ -L "$frames" ] || [ -L "$media/.capture-work" ]; then
  die "Refusing to follow a symlink under docs/media."
fi
if [ -e "$dest" ] && [ "$replace" -eq 0 ]; then
  die "$file already exists. Pass --replace to overwrite it."
fi
if [ -e "$frames" ] && [ "$replace" -eq 0 ]; then
  die "docs/media/${shot}-frames already exists. Pass --replace to replace it."
fi

if [ "$yes" -eq 0 ]; then
  [ -t 0 ] || die "Pass --yes to record without a typed confirmation."
  printf 'Type record to capture %s into docs/media/%s. Zeus will not be launched and system settings will not be changed: ' "$shot" "$file"
  read -r answer
  [ "$answer" = "record" ] || die "Not confirmed. Nothing was written."
fi

cleanup() {
  if [ -n "${work_owned:-}" ] && [ -d "$work" ]; then
    rm -rf "$work"
  fi
}
trap cleanup EXIT

rm -rf "$work"
mkdir -p "$work"
work_owned=1
[ -L "$work" ] && die "Refusing to follow a symlink for the frame directory."

count=$((duration * fps))
[ "$count" -ge 1 ] && [ "$count" -le 144 ] || die "Frame count is out of range."

printf 'Capturing %s frames of %s with screencapture. Arrange the shot yourself.\n' "$count" "$region"
i=0
while [ "$i" -lt "$count" ]; do
  printf -v name 'frame-%03d.png' "$i"
  frame="$work/$name"
  "$capture" -x -t png -R "$region" "$frame"
  [ -f "$frame" ] && [ ! -L "$frame" ] || die "screencapture did not write $name."
  i=$((i + 1))
done

if command -v ffmpeg >/dev/null 2>&1; then
  [ "$replace" -eq 1 ] && rm -f "$dest"
  if ! ffmpeg -y -hide_banner -loglevel error \
    -framerate "$fps" -i "$work/frame-%03d.png" \
    -loop 0 \
    -vf "fps=${fps},scale='min(960,iw)':-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer" \
    "$dest"
  then
    rm -f "$dest"
    die "ffmpeg failed. No GIF was kept."
  fi
  [ -f "$dest" ] && [ ! -L "$dest" ] || die "ffmpeg did not write $file."
  printf 'Wrote docs/media/%s\n' "$file"
else
  rm -rf "$frames"
  mkdir -p "$media"
  mv "$work" "$frames"
  work_owned=
  printf 'ffmpeg is not on PATH. No GIF was written. Frames are in docs/media/%s-frames/ and are not a README asset.\n' "$shot" >&2
  exit 3
fi
