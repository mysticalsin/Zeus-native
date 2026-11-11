#!/usr/bin/env bash
# Install-size budget: fails when the app bundle is larger than BUDGET_MB (default 150). Read-only.
# Language packs install after the app, so the bundle must not grow with language data.
#   scripts/check-bundle-size.sh [build/Zeus.app]
set -euo pipefail
APP="${1:-build/Zeus.app}"
BUDGET_MB="${BUDGET_MB:-150}"
[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 2; }
kb="$(du -sk "$APP" | cut -f1)"
mb=$(( (kb + 1023) / 1024 ))
echo "install size: ${mb} MB (budget ${BUDGET_MB} MB)"
[ "$mb" -le "$BUDGET_MB" ]
