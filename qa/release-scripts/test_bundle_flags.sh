#!/usr/bin/env bash
# Flag parsing and bundle metadata for scripts/bundle.sh.
# Same idea as test_release_scripts.py: fake macOS tools, a throwaway tree, no signing.
# Run from the repository root: bash qa/release-scripts/test_bundle_flags.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fail=0
note() { printf 'FAIL %s\n' "$1" >&2; fail=1; }
ok() { printf 'ok %s\n' "$1"; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/zeus-bundle-flags.XXXXXX")
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

BIN="$WORKDIR/bin"
mkdir -p "$BIN"
for cmd in codesign ditto hdiutil xcrun spctl plutil pgrep mv rm defaults xcode-select swift npm plistbuddy; do
  cat >"$BIN/$cmd" <<EOF
#!$(command -v python3)
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
log = pathlib.Path(os.environ["ZEUS_TEST_LOG"])
with log.open("a") as handle:
    handle.write(name + "\\t" + "\\t".join(args) + "\\n")
if name == "swift" and "--show-bin-path" in args:
    print(os.environ["ZEUS_TEST_BIN"], flush=True)
raise SystemExit(0)
EOF
  chmod 755 "$BIN/$cmd"
done

# The harness keeps real rm/mkdir. Only bundle.sh sees the fake tools.
export PATH="/usr/bin:/bin"

prepare() {
  local tree="$1"
  rm -rf "$tree"
  mkdir -p "$tree/scripts" "$tree/Resources" "$tree/build" "$tree/extension/icons" "$tree/swift-output"
  sed 's|/usr/libexec/PlistBuddy|plistbuddy|g' "$ROOT/scripts/bundle.sh" >"$tree/scripts/bundle.sh"
  chmod 755 "$tree/scripts/bundle.sh"
  cp "$ROOT/scripts/verify-release-signature.sh" "$tree/scripts/verify-release-signature.sh"
  for name in AppIcon.icns Info.plist Logo.png Logo.pdf MenuBarTemplate.png MenuBarTemplate@2x.png NOTICES.txt Zeus.entitlements PrivacyInfo.xcprivacy; do
    printf 'fixture\n' >"$tree/Resources/$name"
  done
  printf 'fixture\n' >"$tree/extension/manifest.json"
  printf 'fixture\n' >"$tree/extension/popup.html"
  mkdir -p "$tree/extension/icons"
  for name in Zeus zeus-hook zeus-bridge zeus-cli; do
    printf 'executable\n' >"$tree/swift-output/$name"
  done
  export ZEUS_TEST_BIN="$tree/swift-output"
  export ZEUS_TEST_LOG="$tree/commands.log"
  : >"$ZEUS_TEST_LOG"
}

run_bundle() {
  local tree="$1"
  shift
  (
    cd "$tree" || exit 1
    export PATH="$BIN:/usr/bin:/bin"
    export ZEUS_TEST_BIN="$tree/swift-output"
    export ZEUS_TEST_LOG="$tree/commands.log"
    bash scripts/bundle.sh "$@"
  )
}

# 1. Unknown flag
prepare "$WORKDIR/unknown"
if run_bundle "$WORKDIR/unknown" --not-a-flag >/tmp/zeus-flag-unknown.out 2>/tmp/zeus-flag-unknown.err; then
  note "unknown flag was accepted"
else
  if grep -q "unknown argument" /tmp/zeus-flag-unknown.err; then
    ok "unknown flag rejected"
  else
    note "unknown flag failed without a clear message: $(cat /tmp/zeus-flag-unknown.err)"
  fi
fi

# 2. --extension-artifact needs a path
prepare "$WORKDIR/needpath"
if run_bundle "$WORKDIR/needpath" --extension-artifact >/tmp/zeus-flag-need.out 2>/tmp/zeus-flag-need.err; then
  note "--extension-artifact with no path was accepted"
else
  if grep -q "needs the path" /tmp/zeus-flag-need.err; then
    ok "artifact flag requires a path"
  else
    note "missing artifact path was unclear: $(cat /tmp/zeus-flag-need.err)"
  fi
fi

# 3. No flag and no node_modules fails clearly, and npm is not run
prepare "$WORKDIR/nonpm"
if run_bundle "$WORKDIR/nonpm" >/tmp/zeus-flag-nonpm.out 2>/tmp/zeus-flag-nonpm.err; then
  note "bundle succeeded with no extension flag and no node_modules"
else
  if grep -q "npm is never run" /tmp/zeus-flag-nonpm.err; then
    ok "missing extension fails closed"
  else
    note "missing extension message: $(cat /tmp/zeus-flag-nonpm.err)"
  fi
fi
if grep -q $'^npm\t' "$WORKDIR/nonpm/commands.log"; then
  note "npm ran when it must not"
else
  ok "npm was not invoked"
fi

# 4. --skip-extension records the skip and does not copy a dist
prepare "$WORKDIR/skip"
if run_bundle "$WORKDIR/skip" --skip-extension >/tmp/zeus-flag-skip.out 2>/tmp/zeus-flag-skip.err; then
  manifest="$WORKDIR/skip/build/Zeus.app/Contents/Resources/ZeusBundleManifest.txt"
  if grep -q "extension: skipped" /tmp/zeus-flag-skip.err && [ -f "$manifest" ] && grep -qx "extension: skipped" "$manifest"; then
    if [ -d "$WORKDIR/skip/build/Zeus.app/Contents/Resources/ChromeExtension" ]; then
      note "skip still copied the extension"
    else
      ok "skip is loud and recorded"
    fi
  else
    note "skip did not record extension: skipped"
  fi
else
  note "skip failed: $(cat /tmp/zeus-flag-skip.err)"
fi

# 5. --extension-artifact copies that directory
prepare "$WORKDIR/art"
mkdir -p "$WORKDIR/prebuilt-dist"
printf 'marker-artifact\n' >"$WORKDIR/prebuilt-dist/marker.txt"
if run_bundle "$WORKDIR/art" --extension-artifact "$WORKDIR/prebuilt-dist" >/tmp/zeus-flag-art.out 2>/tmp/zeus-flag-art.err; then
  copied="$WORKDIR/art/build/Zeus.app/Contents/Resources/ChromeExtension/dist/marker.txt"
  if [ -f "$copied" ] && grep -q marker-artifact "$copied"; then
    ok "artifact dist copied"
  else
    note "artifact dist was not copied to ChromeExtension/dist"
  fi
else
  note "artifact build failed: $(cat /tmp/zeus-flag-art.err)"
fi
if grep -q $'^npm\t' "$WORKDIR/art/commands.log"; then
  note "npm ran for an artifact copy"
fi

# 6. Build number and sha are written into the plist commands
prepare "$WORKDIR/ver"
if ZEUS_BUILD_NUMBER=42 ZEUS_GIT_SHA=abcd1234 run_bundle "$WORKDIR/ver" --skip-extension >/tmp/zeus-flag-ver.out 2>/tmp/zeus-flag-ver.err; then
  log="$WORKDIR/ver/commands.log"
  if grep -q $'plistbuddy\t-c\tSet :CFBundleVersion 42' "$log" && grep -q 'abcd1234' "$log"; then
    ok "version and sha stamped"
  else
    note "version stamp missing from plist commands"
  fi
else
  note "version stamp build failed: $(cat /tmp/zeus-flag-ver.err)"
fi

# 7. Screen-capture usage string. S04-05 owns the sentence below. This plist
# must not declare the key as well: the owner's key plus this file must
# contain NSScreenCaptureUsageDescription exactly once.
owner_sentence='ZEUS captures the screen when you talk with screen consent on, when desktop pointing places a mark, when you record, and for live captions of the sound this Mac is playing. A screenshot is kept only while you are recording.'
local_count=$(grep -c '<key>NSScreenCaptureUsageDescription</key>' "$ROOT/Resources/Info.plist" || true)
owner_count=1
total=$((local_count + owner_count))
if [ "$total" -eq 1 ]; then
  ok "screen capture usage string appears exactly once"
else
  note "NSScreenCaptureUsageDescription appears $total times once the owner key is included (this plist has $local_count; want exactly 1)"
fi
if grep -F -q "$owner_sentence" "$ROOT/Resources/Info.plist"; then
  note "this plist repeats the screen-capture sentence owned by S04-05"
fi
if [ -f "$ROOT/Resources/PrivacyInfo.xcprivacy" ]; then
  ok "privacy manifest file"
else
  note "Resources/PrivacyInfo.xcprivacy is missing"
fi

prepare "$WORKDIR/priv"
printf 'privacy-manifest\n' >"$WORKDIR/priv/Resources/PrivacyInfo.xcprivacy"
if run_bundle "$WORKDIR/priv" --skip-extension >/tmp/zeus-flag-priv.out 2>/tmp/zeus-flag-priv.err; then
  shipped="$WORKDIR/priv/build/Zeus.app/Contents/Resources/PrivacyInfo.xcprivacy"
  if [ -f "$shipped" ] && grep -q privacy-manifest "$shipped"; then
    ok "privacy manifest copied"
  else
    note "privacy manifest was not copied into the app"
  fi
else
  note "privacy copy build failed: $(cat /tmp/zeus-flag-priv.err)"
fi

if [ "$fail" -ne 0 ]; then
  printf 'bundle flag tests failed\n' >&2
  exit 1
fi
printf 'bundle flag tests passed\n'
exit 0
