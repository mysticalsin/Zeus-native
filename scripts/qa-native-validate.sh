#!/usr/bin/env bash
# Exit 0 only when every scripted step passed and has a real screenshot.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
exec python3 -I "$repo/qa/native-qa/validate.py" "$@"
