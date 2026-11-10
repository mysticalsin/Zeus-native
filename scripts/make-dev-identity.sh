#!/bin/bash
# Creates a stable, self-signed code-signing identity "Zeus Local Dev" for local builds, so every
# rebuild carries the same designated requirement and keeps its Keychain access (no prompts).
# It lives in its own keychain (~/Library/Keychains/zeus-dev.keychain-db) whose random password
# is kept in ~/.zeus/devkeychain.pass (mode 600), so nothing here asks for a password
# and the login keychain is untouched. Idempotent. Never prints a secret.
set -euo pipefail
NAME="Zeus Local Dev"
DIR="$HOME/.zeus-dev/codesign"
KC="$HOME/Library/Keychains/zeus-dev.keychain-db"
mkdir -p "$DIR"; chmod 700 "$HOME/.zeus-dev" "$DIR"

if [ -f "$KC" ] && security find-certificate -c "$NAME" "$KC" >/dev/null 2>&1; then
  echo "identity: $NAME already present in zeus-dev keychain"
else
  umask 077
  mkdir -p "$HOME/.zeus"; chmod 700 "$HOME/.zeus"
  [ -f "$HOME/.zeus/devkeychain.pass" ] || openssl rand -hex 24 > "$HOME/.zeus/devkeychain.pass"
  chmod 600 "$HOME/.zeus/devkeychain.pass"
  PASS="$(cat "$HOME/.zeus/devkeychain.pass")"
  cat > "$DIR/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$DIR/cert.cnf" \
    -keyout "$DIR/dev.key" -out "$DIR/dev.crt" >/dev/null 2>&1
  P12PASS="$(openssl rand -hex 16)"
  openssl pkcs12 -export -inkey "$DIR/dev.key" -in "$DIR/dev.crt" -name "$NAME" \
    -passout "pass:$P12PASS" -out "$DIR/dev.p12" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1
  [ -f "$KC" ] || security create-keychain -p "$PASS" "$KC"
  security set-keychain-settings "$KC"               # no auto-lock timeout
  security unlock-keychain -p "$PASS" "$KC"
  security import "$DIR/dev.p12" -k "$KC" -P "$P12PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  # Let codesign use the key without a dialog (allowed because we know this keychain's password).
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
  rm -f "$DIR/dev.p12"
  echo "identity: created $NAME"
fi

# Keep the keychain in the user search list so codesign finds it.
if ! security list-keychains -d user | grep -q "zeus-dev.keychain-db"; then
  # shellcheck disable=SC2046
  security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') "$KC"
  echo "search list: added zeus-dev keychain"
fi
security find-identity -p codesigning "$KC" | grep -q "$NAME" && echo "ok: $NAME usable for codesign"
