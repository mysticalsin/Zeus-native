#!/usr/bin/env bash
# Signs a dev license key. The private key lives in ~/.zeus-dev (outside the repo, git-ignored).
set -euo pipefail
exec swift "$(dirname "$0")/make-license.swift" "$@"
