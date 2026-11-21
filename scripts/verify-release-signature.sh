#!/usr/bin/env bash
# Checks the Developer ID, secure timestamp and hardened runtime on the app and every helper.
# The team identifier and the app bundle identifier below are the only accepted values.
# codesign --display prints those fields. It does not prove the bytes match the signature,
# so each binary also has to pass codesign --verify --strict.
set -euo pipefail
APP="${1:?Usage: scripts/verify-release-signature.sh path/to/Zeus.app}"
# Shipping bundle identifier. Resources/Info.plist carries the same value.
EXPECTED_BUNDLE_ID="app.zeus.mac"
# Apple Developer Team ID. A TeamIdentifier that is merely well-formed is not accepted.
# This repository has no other record of the team, and this script does not read the Keychain.
# ZEUSTEAMID is an explicit fail-closed placeholder. It is not Tony's Apple Team ID.
# MERGE-BLOCKED: needs Tony's Apple Team ID. While this literal is ZEUSTEAMID the
# script refuses every release, including a binary whose TeamIdentifier is ZEUSTEAMID.
# Replace this literal only in a reviewed change when Tony's Developer ID team is known.
EXPECTED_TEAM_ID="ZEUSTEAMID"
if [ "$EXPECTED_TEAM_ID" = "ZEUSTEAMID" ]; then
  echo "Release signature rejected: EXPECTED_TEAM_ID is the placeholder ZEUSTEAMID. MERGE-BLOCKED: needs Tony's Apple Team ID." >&2
  exit 1
fi
# An empty, short, long, lowercase, or symbolic team is not a team id. The compare is never skipped.
if ! [[ "$EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Release signature rejected: EXPECTED_TEAM_ID must be 10 characters from A-Z and 0-9." >&2
  exit 1
fi
requirement="certificate leaf[subject.OU] = ${EXPECTED_TEAM_ID}"
codesign --verify --deep --strict -R "$requirement" "$APP"
for binary in "$APP" "$APP"/Contents/Helpers/* "$APP"/Contents/Resources/zeus-now-playing; do
  if [ ! -e "$binary" ]; then
    case "$binary" in
      *'/Contents/Helpers/*')
        # The Helpers glob did not expand. There is no helper file on that path.
        continue
        ;;
    esac
    echo "Release signature rejected: expected binary is missing: $binary" >&2
    exit 1
  fi
  codesign --verify --strict -R "$requirement" "$binary"
  details="$(codesign --display --verbose=4 "$binary" 2>&1)"
  team="$(awk -F= '/^TeamIdentifier=/{print $2; exit}' <<<"$details")"
  if ! [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || [ "$team" != "$EXPECTED_TEAM_ID" ] \
    || ! grep -q '^Authority=Developer ID Application:' <<<"$details" \
    || ! grep -q '^Timestamp=' <<<"$details" \
    || grep -Eq '^Timestamp=(none|invalid)$' <<<"$details" \
    || ! grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$details"; then
    echo "Release signature rejected: $binary needs the pinned team, Developer ID, a secure timestamp and hardened runtime." >&2
    exit 1
  fi
  if [ "$binary" = "$APP" ]; then
    identifier="$(awk -F= '/^Identifier=/{print $2; exit}' <<<"$details")"
    if [ "$identifier" != "$EXPECTED_BUNDLE_ID" ]; then
      echo "Release signature rejected: $binary identifier is not $EXPECTED_BUNDLE_ID." >&2
      exit 1
    fi
  fi
done
