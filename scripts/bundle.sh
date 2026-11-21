#!/usr/bin/env bash
# Builds ZEUS and assembles build/Zeus.app (app + helpers), signed with hardened runtime.
#   scripts/bundle.sh                  signs with "Zeus Local Dev" when scripts/make-dev-identity.sh
#                                      has created it, otherwise ad hoc
#   SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh
# The stable local identity keeps the same designated requirement on every rebuild, so Keychain
# access and privacy permissions survive rebuilds (an ad-hoc signature changes every build).
set -euo pipefail
cd "$(dirname "$0")/.."

# The browser extension is never built here. npm ci counts as an install and is refused
# on a locked-down Mac. Pass a dist that was built elsewhere, or skip it on purpose.
EXTENSION_MODE=""
EXTENSION_ARTIFACT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-extension)
      if [ -n "$EXTENSION_MODE" ]; then
        echo "error: pass only one of --skip-extension or --extension-artifact." >&2
        exit 1
      fi
      EXTENSION_MODE=skip
      shift
      ;;
    --extension-artifact)
      if [ -n "$EXTENSION_MODE" ]; then
        echo "error: pass only one of --skip-extension or --extension-artifact." >&2
        exit 1
      fi
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        echo "error: --extension-artifact needs the path of a prebuilt extension dist." >&2
        exit 1
      fi
      EXTENSION_MODE=artifact
      EXTENSION_ARTIFACT=$2
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

CONFIG="${CONFIG:-release}"
if [ "${RELEASE:-0}" = 1 ] && [ "$CONFIG" != release ]; then
  echo "Release builds must use CONFIG=release (CONFIG=$CONFIG)." >&2
  exit 1
fi
if [ "${RELEASE:-0}" = 1 ] && { [ -z "${SIGN_IDENTITY:-}" ] || [ "${SIGN_IDENTITY:-}" = - ]; }; then
  echo "Release builds require an explicit Developer ID Application signing identity." >&2
  exit 1
fi
DEV_KC="$HOME/Library/Keychains/zeus-dev.keychain-db"
DEV_PASS_FILE="$HOME/.zeus/devkeychain.pass"
[ -f "$DEV_PASS_FILE" ] || DEV_PASS_FILE="$HOME/.zeus-dev/codesign/keychain-pass"
KC_ARGS=()
LOCAL_IDENTITY=0
if [ -z "${SIGN_IDENTITY:-}" ] && [ -f "$DEV_KC" ] && [ -f "$DEV_PASS_FILE" ]; then
  security unlock-keychain -p "$(cat "$DEV_PASS_FILE")" "$DEV_KC"
  SIGN_IDENTITY="$(security find-identity -p codesigning "$DEV_KC" | awk '/"Zeus Local Dev"/{print $2; exit}')"
  [ -n "$SIGN_IDENTITY" ] && KC_ARGS=(--keychain "$DEV_KC") && LOCAL_IDENTITY=1 && echo "Signing with Zeus Local Dev"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
TIMESTAMP_ARGS=(--timestamp)
if [ "$SIGN_IDENTITY" = - ] || [ "$LOCAL_IDENTITY" = 1 ]; then
  TIMESTAMP_ARGS=(--timestamp=none)
fi
APP="build/Zeus.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
GIT_SHA="${ZEUS_GIT_SHA:-}"
if [ -z "$GIT_SHA" ]; then
  GIT_SHA="$(git rev-parse --short=8 HEAD 2>/dev/null || true)"
fi
BUILD_NUMBER="${ZEUS_BUILD_NUMBER:-}"
if [ -z "$BUILD_NUMBER" ]; then
  BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || true)"
fi
STAMP="$(date +%Y%m%d%H%M%S)"
if [ -n "$GIT_SHA" ]; then
  STAMP="${STAMP}-${GIT_SHA}"
fi
STAMP="${STAMP}-$$"
/usr/libexec/PlistBuddy -c "Add :ZeusBuildStamp string ${STAMP}" "$APP/Contents/Info.plist" >/dev/null
if [ -n "$BUILD_NUMBER" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$APP/Contents/Info.plist" >/dev/null
fi
if [ -n "${ZEUS_MARKETING_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${ZEUS_MARKETING_VERSION}" "$APP/Contents/Info.plist" >/dev/null
fi
cp Resources/AppIcon.icns Resources/Logo.png Resources/Logo.pdf Resources/MenuBarTemplate.png Resources/MenuBarTemplate@2x.png \
  Resources/NOTICES.txt Resources/PrivacyInfo.xcprivacy \
  "$APP/Contents/Resources/"
cp "$BIN/Zeus" "$APP/Contents/MacOS/Zeus"
cp "$BIN/zeus-hook" "$BIN/zeus-bridge" "$APP/Contents/Helpers/"
cp "$BIN/zeus-cli" "$APP/Contents/Helpers/zeus"
# SwiftPM resource bundles (Zeus avatar art + dependencies like FluidAudio) live under Resources so the app signature stays sealed.
# Test-target resource bundles (*Tests.bundle) hold fixtures only and never ship in the app.
for bundle in "$BIN"/*.bundle; do
  [[ -e "$bundle" ]] || continue
  [[ "$(basename "$bundle")" == *Tests.bundle ]] && continue
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# The browser extension ships inside the app when a dist is already on disk.
# This script never runs npm. A prebuilt dist is copied, or the skip is written into the bundle.
MANIFEST="$APP/Contents/Resources/ZeusBundleManifest.txt"
case "$EXTENSION_MODE" in
  skip)
    echo "warning: browser extension skipped (--skip-extension). extension: skipped. npm is never run by this script." >&2
    printf 'extension: skipped\n' >"$MANIFEST"
    /usr/libexec/PlistBuddy -c "Add :ZeusExtensionStatus string skipped" "$APP/Contents/Info.plist" >/dev/null
    ;;
  artifact)
    if [ ! -d "$EXTENSION_ARTIFACT" ]; then
      echo "error: --extension-artifact is not a directory: $EXTENSION_ARTIFACT" >&2
      exit 1
    fi
    mkdir -p "$APP/Contents/Resources/ChromeExtension"
    cp extension/manifest.json "$APP/Contents/Resources/ChromeExtension/"
    cp -R "$EXTENSION_ARTIFACT" "$APP/Contents/Resources/ChromeExtension/dist"
    cp -R extension/icons extension/popup.html "$APP/Contents/Resources/ChromeExtension/"
    printf 'extension: artifact\n' >"$MANIFEST"
    ;;
  *)
    if [ -d extension/node_modules ] && [ -d extension/dist ]; then
      mkdir -p "$APP/Contents/Resources/ChromeExtension"
      cp extension/manifest.json "$APP/Contents/Resources/ChromeExtension/"
      cp -R extension/dist extension/icons extension/popup.html "$APP/Contents/Resources/ChromeExtension/"
      printf 'extension: prebuilt\n' >"$MANIFEST"
    else
      echo "error: browser extension is not bundled. Pass --extension-artifact <dist> or --skip-extension. npm is never run by this script. node_modules is absent, so there is no prebuilt dist to copy." >&2
      exit 1
    fi
    ;;
esac

# Lean install: debug info and local symbols are not needed to run. Dynamic symbols stay, so behaviour is
# unchanged; dSYMs are never copied into the app. Done before signing, which seals the stripped files.
# ZEUS_KEEP_SYMBOLS=1 keeps them for a profiling build.
if [ "${ZEUS_KEEP_SYMBOLS:-0}" != 1 ]; then
  for bin in "$APP/Contents/MacOS/Zeus" "$APP/Contents/Helpers/"*; do
    xcrun strip -S -x "$bin"
  done
fi

for helper in "$APP/Contents/Helpers/"*; do
  codesign --force --options runtime "${TIMESTAMP_ARGS[@]}" ${KC_ARGS[@]+"${KC_ARGS[@]}"} --sign "$SIGN_IDENTITY" "$helper"
done
codesign --force --options runtime "${TIMESTAMP_ARGS[@]}" --entitlements Resources/Zeus.entitlements \
  ${KC_ARGS[@]+"${KC_ARGS[@]}"} --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
if [ "${RELEASE:-0}" = 1 ]; then scripts/verify-release-signature.sh "$APP"; fi

# Local identity only: macOS pins Keychain items made by a binary without a Team ID to its cdhash.
# Add this build's cdhashes (app and helpers) to the partition list of every com.zeus.app item in
# the zeus-dev keychain, using that keychain's own password: silent, and the login keychain is
# never touched. The last 16 builds stay trusted so worktrees can share the items.
if [ "$LOCAL_IDENTITY" = 1 ]; then
  HASHES="$HOME/.zeus-dev/codesign/cdhashes"
  touch "$HASHES"
  for bin in "$APP/Contents/MacOS/Zeus" "$APP/Contents/Helpers/"*; do
    codesign -dvvv "$bin" 2>&1 | awk -F= '/^CDHash=/{print "cdhash:"$2}' >> "$HASHES"
  done
  tail -n 16 "$HASHES" | awk '!seen[$0]++' > "$HASHES.tmp" && mv "$HASHES.tmp" "$HASHES"
  LIST="apple-tool:,apple:,$(paste -sd, "$HASHES")"
  PASS="$(cat "$DEV_PASS_FILE")"
  count=0
  while IFS= read -r acct; do
    [ -n "$acct" ] || continue
    security set-generic-password-partition-list -S "$LIST" -s com.zeus.app -a "$acct" -k "$PASS" "$DEV_KC" >/dev/null 2>&1 && count=$((count+1))
  done < <(security dump-keychain "$DEV_KC" 2>/dev/null | awk '/^keychain:/{a=""} /"acct"<blob>=/{a=$0; sub(/.*"acct"<blob>="/,"",a); sub(/"$/,"",a)} /"svce"<blob>="com.zeus.app"/{if(a!="")print a}' | sort -u)
  unset PASS
  echo "Keychain: this build trusted on $count com.zeus.app items in zeus-dev"
fi
echo "Built $APP"
