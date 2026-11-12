#!/usr/bin/env bash
# Human-style end-to-end QA of a packaged Zeus.app. Run it yourself, from a terminal that has Accessibility
# access. It drives the real app through the Accessibility API like a person clicking, and records evidence.
#
#   bash scripts/human-qa.sh <path/to/Zeus.app> [--screenshots] [--only <journey>] [--allow-mic] [--yes]
#
# Journeys: launch topbar settings record scribe alerts talk (quit and the restart check run only on a full run).
# Evidence: ~/AI-Brain-build/zeus-human-qa/<timestamp>/ (report.md, receipt.json, logs, freeze samples).
# It never requests a permission, never uses the microphone without --allow-mic, never starts a recording
# (the Record countdown is cancelled with Esc) and refuses to run in CI. See docs/HUMAN-QA.md.
set -euo pipefail
umask 077

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
py="$repo/qa/closed-loop/human_qa.py"
BUNDLE_ID="app.zeus.mac"
BASE="$HOME/AI-Brain-build/zeus-human-qa"

die() { echo "human-qa: $*" >&2; exit "${2:-2}"; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only"
[ -z "${CI:-}${GITHUB_ACTIONS:-}" ] || die "refusing to run in CI. It needs a logged-in Mac with a screen."

APP=""; SHOTS=""; ONLY=""; MIC=""; YES=""
while [ $# -gt 0 ]; do
    case "$1" in
        --screenshots) SHOTS="--screenshots" ;;
        --only) shift; ONLY="${1:-}"; [ -n "$ONLY" ] || die "--only needs a journey name" 64 ;;
        --allow-mic) MIC="--allow-mic" ;;
        --yes) YES=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        -*) die "unknown option $1" 64 ;;
        *) [ -z "$APP" ] || die "one app path only" 64; APP="$1" ;;
    esac
    shift
done
[ -n "$APP" ] || die "usage: human-qa.sh <path/to/Zeus.app> [--screenshots] [--only <journey>] [--allow-mic] [--yes]" 64
case "$ONLY" in ""|launch|topbar|settings|record|scribe|alerts|talk) ;; *) die "unknown journey '$ONLY'" 64 ;; esac

# 1. The app must be a real bundle outside the repository (the check lives in human_qa.py, selftested).
APP="$(python3 -I "$py" check-app "$APP")" || die "refusing: not a usable app bundle outside the repo" 2

# 2. Never share the single-instance guard with your own running Zeus.
if pgrep -x Zeus >/dev/null 2>&1; then
    die "Zeus is already running. Quit it first; this script will not touch your running copy." 2
fi

# 3. Zeus has no throwaway settings domain for full GUI runs (--qa-startup is a probe only), so say so.
echo "WARNING: this run uses your REAL Zeus settings ($BUNDLE_ID)."
echo "It flips 'Show Zeus in screen shares' and moves the top bar position, then restores both at the end."
echo "A copy of your settings is saved first. It moves your mouse to the top of the screen and types in Zeus."
if [ -z "$YES" ]; then
    printf "Continue? [y/N] "
    read -r answer </dev/tty || answer=""
    case "$answer" in y|Y|yes|YES) ;; *) die "cancelled" 1 ;; esac
fi

# 4. Evidence folder, driver build (plain swiftc, cached by source hash, never swift build).
EV="$(python3 -I "$py" new-dir "$BASE")"
CACHE="$HOME/AI-Brain-build/zeus-human-qa/.cache"
mkdir -p "$CACHE"
SUM="$(shasum -a 256 "$here/human-qa.swift" | cut -c1-16)"
BIN="$CACHE/human-qa-$SUM"
if [ ! -x "$BIN" ]; then
    echo "Compiling the driver..."
    xcrun swiftc -O -swift-version 5 -o "$BIN" "$here/human-qa.swift" 2> "$EV/compile.log" \
        || { cat "$EV/compile.log" >&2; die "the driver did not compile" 3; }
fi

# 5. Accessibility trust for this terminal. The check never prompts.
if ! "$BIN" --check-trust >/dev/null 2>&1; then
    cat >&2 <<MSG
human-qa: this terminal is not allowed to control the computer.
Open System Settings > Privacy & Security > Accessibility, switch on the terminal app you are using
(Terminal, iTerm, Ghostty...), quit and reopen it, then run this script again.
MSG
    exit 2
fi

# 6. Back up what the run touches: the app's defaults domain.
defaults export "$BUNDLE_ID" "$EV/defaults-before.plist" 2>/dev/null || echo "(no saved settings yet)" > "$EV/defaults-before.plist"

STARTED="$(python3 -c 'import time; print(time.time())')"
LOGPID=""; APPPID=""
cleanup() { [ -z "$LOGPID" ] || kill "$LOGPID" 2>/dev/null || true; }
trap cleanup EXIT

# 7. Unified log of the app, to a file.
log stream --predicate 'process == "Zeus"' > "$EV/zeus-log.txt" 2>/dev/null &
LOGPID=$!

launch_app() {
    LAUNCHED_AT="$(python3 -c 'import time; print(time.time())')"
    open -n "$APP"
    APPPID=""
    for _ in $(seq 1 100); do
        APPPID="$(pgrep -x Zeus | head -n 1 || true)"
        [ -z "$APPPID" ] || return 0
        sleep 0.1
    done
    die "Zeus did not start within 10 s" 3
}

DRIVER_RC=0
launch_app
echo "Zeus pid $APPPID. Evidence: $EV"
# shellcheck disable=SC2086
"$BIN" --pid "$APPPID" --app "$APP" --bundle-id "$BUNDLE_ID" --phase main --evidence "$EV" \
    --launched-at "$LAUNCHED_AT" ${ONLY:+--only "$ONLY"} $SHOTS $MIC || DRIVER_RC=$?

# 8. Quit, relaunch, check the settings persisted, restore them (full runs only).
if [ -z "$ONLY" ]; then
    for _ in $(seq 1 100); do pgrep -x Zeus >/dev/null 2>&1 || break; sleep 0.1; done
    if pgrep -x Zeus >/dev/null 2>&1; then
        echo "Zeus did not quit; asking it to quit again before the relaunch." >&2
        kill -TERM "$APPPID" 2>/dev/null || true
        sleep 2
    fi
    if [ -f "$EV/state.json" ]; then
        launch_app
        PRC=0
        "$BIN" --pid "$APPPID" --app "$APP" --bundle-id "$BUNDLE_ID" --phase persist --evidence "$EV" \
            --launched-at "$LAUNCHED_AT" $SHOTS || PRC=$?
        [ "$PRC" -eq 0 ] || DRIVER_RC=$PRC
    else
        echo "No state.json (the topbar journey did not finish): skipping the restart check." >&2
        DRIVER_RC=1
    fi
else
    echo "Partial run (--only $ONLY): Zeus is left running and any setting the journey changed is not restored."
fi

# 9. Stop the log, collect crash reports since the start, write the report.
sleep 2
cleanup; LOGPID=""
CRASHES=()
while IFS= read -r f; do [ -z "$f" ] || { CRASHES+=(--crash "$f"); cp "$f" "$EV/" 2>/dev/null || true; }; done \
    < <(python3 -I "$py" crashes "$STARTED")
set +e
python3 -I "$py" finalize --evidence "$EV" --app "$APP" --started "$STARTED" --driver-rc "$DRIVER_RC" \
    ${ONLY:+--only "$ONLY"} "${CRASHES[@]+"${CRASHES[@]}"}"
RC=$?
set -e
echo
echo "Report:  $EV/report.md"
echo "Receipt: $EV/receipt.json"
ls "$EV"/freeze-*.sample.txt >/dev/null 2>&1 && echo "Freeze samples: $(ls "$EV"/freeze-*.sample.txt | wc -l | tr -d ' ') in $EV"
echo "Your settings before the run: $EV/defaults-before.plist (restore with: defaults import $BUNDLE_ID <that file>, with Zeus quit)"
exit "$RC"
