#!/usr/bin/env bash
# Every option id the app reads must exist in the generated catalog, and the catalog must be fresh.
set -euo pipefail
cd "$(dirname "$0")/.."
catalog=Sources/Zeus/App/SettingsCatalog.swift
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Sources/Zeus/App"
python3 scripts/gen-settings-catalog.py "$tmp" "$tmp/inventory.md"
diff -q "$tmp/$catalog" "$catalog" >/dev/null || { echo "catalog is stale: run scripts/gen-settings-catalog.py"; exit 1; }
python3 qa/closed-loop/tests/test_settings_catalog.py
missing=0
for id in $(grep -rhoE 'SettingsStore\.shared\.(bool|string|double|words)\("[^"]+"\)|options\.(bool|words)\("[^"]+"\)|store\.(bool|set)\("[^"]+"' Sources/Zeus | grep -oE '"[^"]+"' | tr -d '"' | sort -u); do
  grep -q "id: \"$id\"" "$catalog" || { echo "missing in catalog: $id"; missing=1; }
done
echo "catalog ids: $(grep -c 'SettingOption(id:' "$catalog")"
exit $missing
