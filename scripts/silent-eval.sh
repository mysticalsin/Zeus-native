#!/usr/bin/env bash
# O38: fake-Mac silent eval gate. No real Mac actions, no AI spend.
# Run through the swarm lock from repo root, for example:
#   ~/dev/zeus-wt/glance-clone-proof/tools/swarm-lock.sh bash scripts/silent-eval.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPORT="${ZEUS_SILENT_EVAL_REPORT:-qa/O38/silent-eval-last.json}"
mkdir -p "$(dirname "$REPORT")"
LOG_DIR="${ZEUS_SILENT_EVAL_LOG_DIR:-$HOME/dev/zeus-wt/glance-clone-proof/qa/swarm/E}"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/silent-eval-$STAMP.log"
swift run zeus-silent-eval --out "$REPORT" 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"
