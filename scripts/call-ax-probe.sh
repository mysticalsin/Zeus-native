#!/bin/bash
# Wrapper for call-ax-probe.swift. Compiles to a temp binary, then runs it with your arguments.
# Run from Terminal (granted Accessibility) during a live call.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -O -o "$tmp/call-ax-probe" "$here/call-ax-probe.swift"
"$tmp/call-ax-probe" "$@"
