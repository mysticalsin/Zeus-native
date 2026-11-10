#!/bin/bash
# One-time move of the old com.zeus.worker items (created by the `security` CLI, so the app
# cannot read them without a dialog) into com.zeus.app. `security` is on those items' access
# list, so this raises no prompt; values go through a pipe and are never printed.
set -uo pipefail
cd "$(dirname "$0")/.."
ZEUS="${ZEUS:-build/Zeus.app/Contents/MacOS/Zeus}"
for pair in "url:worker.url" "token:worker.token"; do
  old="${pair%%:*}"; new="${pair##*:}"
  if security find-generic-password -s com.zeus.worker -a "$old" >/dev/null 2>&1; then
    security find-generic-password -s com.zeus.worker -a "$old" -w 2>/dev/null | "$ZEUS" --keychain-import "$new"
  else
    echo "{\"account\":\"$new\",\"skipped\":\"no legacy item\"}"
  fi
done
