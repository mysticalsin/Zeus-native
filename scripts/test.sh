#!/usr/bin/env bash
# Runs the test suite. With only the Command Line Tools installed (no Xcode), SwiftPM
# does not find the Swift Testing macro plugin on its own, so point it there.
set -euo pipefail
cd "$(dirname "$0")/.."

# Tests use throwaway UserDefaults suites (zeus.*.<UUID>, zeus.tests.onboarding.<name>). Remove them
# afterwards, pass or fail, so runs don't pile up preference files. The app's own domains are never matched.
clean_test_defaults() {
  local uuid='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
  defaults domains | tr ',' '\n' | sed 's/^ *//' \
    | { grep -E "^zeus\.[A-Za-z0-9._-]*\.${uuid}\$|^zeus\.tests\.onboarding\.[A-Za-z]+\$" || true; } \
    | while read -r domain; do
        defaults delete "$domain" >/dev/null 2>&1 || true
        rm -f "$HOME/Library/Preferences/$domain.plist" # an emptied domain otherwise stays as a stub file
      done
}
trap clean_test_defaults EXIT

PLUGIN_DIR="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGIN_DIR" ]]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
else
  swift test "$@"
fi
