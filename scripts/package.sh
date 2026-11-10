#!/usr/bin/env bash
# Builds build/ZEUS.dmg: Zeus.app plus an Applications shortcut, with the Z-bolt volume icon.
# Local preview: scripts/package.sh
# Release: RELEASE=1 SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=zeus scripts/package.sh
# The notary profile must already exist in the user's keychain. No credentials are read from chat or files here.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${RELEASE:-0}" = 1 ]; then
  if [ -z "${SIGN_IDENTITY:-}" ] || [ "${SIGN_IDENTITY:-}" = - ] || [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "Release packaging requires SIGN_IDENTITY and an existing NOTARY_PROFILE." >&2
    exit 1
  fi
fi
scripts/bundle.sh
STAGE=$(mktemp -d build/.zeus-package.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
notarize() {
  local artifact="$1" receipt="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$receipt"
  if [ "$(plutil -extract status raw -o - "$receipt")" != Accepted ]; then
    echo "Notarization was not accepted; see $receipt. No release DMG was published." >&2
    exit 1
  fi
}
if [ "${RELEASE:-0}" = 1 ]; then
  ditto -c -k --keepParent build/Zeus.app "$STAGE/Zeus.zip"
  notarize "$STAGE/Zeus.zip" build/Zeus-app-notary.json
  xcrun stapler staple build/Zeus.app
  xcrun stapler validate build/Zeus.app
  spctl --assess --type execute --verbose=2 build/Zeus.app
fi
mkdir "$STAGE/image"
ditto build/Zeus.app "$STAGE/image/Zeus.app"
ln -s /Applications "$STAGE/image/Applications"
cp Resources/AppIcon.icns "$STAGE/image/.VolumeIcon.icns"
hdiutil create -quiet -volname "ZEUS" -srcfolder "$STAGE/image" -fs HFS+ -format UDZO "$STAGE/ZEUS.dmg"
if [ "${RELEASE:-0}" = 1 ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$STAGE/ZEUS.dmg"
  notarize "$STAGE/ZEUS.dmg" build/Zeus-dmg-notary.json
  xcrun stapler staple "$STAGE/ZEUS.dmg"
  xcrun stapler validate "$STAGE/ZEUS.dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$STAGE/ZEUS.dmg"
fi
# Keep the last good DMG if any build, submission, stapling or assessment step fails.
mv -f "$STAGE/ZEUS.dmg" build/ZEUS.dmg
shasum -a 256 build/ZEUS.dmg > build/ZEUS.dmg.sha256
if [ "${RELEASE:-0}" != 1 ]; then echo "Local preview only: this DMG has not been notarized or Gatekeeper approved."; fi
echo "Built build/ZEUS.dmg ($(du -h build/ZEUS.dmg | cut -f1))"
