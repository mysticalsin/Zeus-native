#!/bin/bash
# Inspect-only QA artifact check for an already-built Zeus.app. It never starts the app.
#
#   bash scripts/qa-startup-launch.sh <Zeus.app> --expect-binary-sha256 <hex> --expect-manifest-sha256 <hex>
#
# --exec is refused unconditionally (exit 78): there is no independent OS isolation yet, so no launch is
# permitted, even for QA. This script has no watchdog, no process groups, no signals and no child app.
# Inspection binds the exact artifact: absolute non-symlink path, parent owned by this user with mode 700,
# bundle identifier app.zeus.mac, no symlinks or special files in the bundle, the Contents/MacOS/Zeus SHA-256,
# and the manifest digest. Manifest format zeus-manifest-v1: a compact JSON object of bundle-relative path to
# lowercase file SHA-256, keys sorted by byte order, no whitespace or trailing newline; the digest is the
# SHA-256 of that text. Expected hashes come from arguments only; nothing is read from the inherited environment.
# It creates nothing, deletes nothing and changes no setting.
set -euo pipefail
umask 077
PATH=/usr/bin:/bin
LC_ALL=C
export PATH LC_ALL
unset BASH_ENV ENV CDPATH 2>/dev/null || true

usage() {
    echo "usage: bash scripts/qa-startup-launch.sh <Zeus.app> --expect-binary-sha256 <hex> --expect-manifest-sha256 <hex>" >&2
    exit 64
}
die() {
    echo "qa-startup-launch: $*" >&2
    exit 78
}

app=""
want_binary=""
want_manifest=""
while [ $# -gt 0 ]; do
    case "$1" in
        --exec) die "--exec is refused: launching the app needs independent OS isolation that does not exist" ;;
        --expect-binary-sha256) [ $# -ge 2 ] || usage; want_binary="$2"; shift 2 ;;
        --expect-manifest-sha256) [ $# -ge 2 ] || usage; want_manifest="$2"; shift 2 ;;
        -*) usage ;;
        *) [ -z "$app" ] || usage; app="$1"; shift ;;
    esac
done
[ -n "$app" ] || usage
[ -n "$want_binary" ] || die "--expect-binary-sha256 is required"
[ -n "$want_manifest" ] || die "--expect-manifest-sha256 is required"

is_sha256() {
    case "$1" in *[!0-9a-f]*) return 1 ;; esac
    [ "${#1}" -eq 64 ]
}
is_sha256 "$want_binary" || die "--expect-binary-sha256 is not 64 lowercase hex digits"
is_sha256 "$want_manifest" || die "--expect-manifest-sha256 is not 64 lowercase hex digits"

# The path: absolute, standard form, conservative characters, a .app bundle.
case "$app" in /*) ;; *) die "app path is not absolute" ;; esac
case "$app" in *[!A-Za-z0-9._/+-]*) die "app path has characters outside A-Za-z0-9._/+-" ;; esac
case "$app" in *.app) ;; *) die "not a .app bundle: $app" ;; esac
case "$app" in *//*|*/./*|*/../*|*/.|*/..) die "app path is not in standard form" ;; esac

# No component from / down may be a symlink (so /tmp and /var must be given as /private/...).
rest=${app#/}
current=""
while [ -n "$rest" ]; do
    part=${rest%%/*}
    if [ "$part" = "$rest" ]; then rest=""; else rest=${rest#*/}; fi
    current="$current/$part"
    [ ! -L "$current" ] || die "path component is a symlink: $current"
done

[ -d "$app" ] || die "no such app bundle: $app"
parent=${app%/*}
[ -n "$parent" ] || die "app has no parent directory"
parent_facts=$(/usr/bin/stat -f '%u %Lp' "$parent") || die "cannot stat the parent directory"
[ "$parent_facts" = "$(/usr/bin/id -u) 700" ] || die "parent directory is not owned by this user with mode 700"

info_plist="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/Zeus"
{ [ -f "$info_plist" ] && [ ! -L "$info_plist" ]; } || die "Info.plist is missing or a symlink"
{ [ -f "$binary" ] && [ ! -L "$binary" ] && [ -x "$binary" ]; } || die "Contents/MacOS/Zeus is missing, a symlink or not executable"
bundle_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info_plist") || die "no CFBundleIdentifier"
[ "$bundle_id" = "app.zeus.mac" ] || die "bundle identifier is not app.zeus.mac"

file_hash() {
    local line
    line=$(/usr/bin/shasum -a 256 "$1") || die "cannot hash $1"
    line=${line%% *}
    is_sha256 "$line" || die "unexpected hash output for $1"
    echo "$line"
}

# Only regular files and directories may exist anywhere in the bundle.
odd=$(/usr/bin/find "$app" ! -type f ! -type d -print -quit) || die "cannot scan the bundle"
[ -z "$odd" ] || die "bundle holds a symlink or special file"

binary_hash=$(file_hash "$binary")

manifest="{"
separator=""
count=0
while IFS= read -r -d '' file; do
    relative=${file#"$app"/}
    case "$relative" in ''|"$file"|*[!A-Za-z0-9._/+\ @-]*) die "bundle file name is not JSON-safe: $relative" ;; esac
    hash=$(file_hash "$file")
    manifest="$manifest$separator\"$relative\":\"$hash\""
    separator=","
    count=$((count + 1))
done < <(/usr/bin/find "$app" -type f -print0 | /usr/bin/sort -z)
manifest="$manifest}"
manifest_hash=$(printf '%s' "$manifest" | /usr/bin/shasum -a 256)
manifest_hash=${manifest_hash%% *}
is_sha256 "$manifest_hash" || die "unexpected manifest digest output"

echo "INSPECT ONLY (nothing created, nothing started; --exec is refused)"
echo "app:             $app ($bundle_id)"
echo "binary sha256:   $binary_hash"
echo "manifest:        zeus-manifest-v1, $count files"
echo "manifest sha256: $manifest_hash"

[ "$binary_hash" = "$want_binary" ] || die "binary sha256 does not match the expected value"
[ "$manifest_hash" = "$want_manifest" ] || die "manifest sha256 does not match the expected value"
# The binary must not have changed while it was being inspected.
[ "$(file_hash "$binary")" = "$want_binary" ] || die "binary changed during inspection"
echo "artifact binding: OK (static check only; not a runtime isolation proof)"
