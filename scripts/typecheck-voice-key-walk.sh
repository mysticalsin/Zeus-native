#!/bin/sh
# Typecheck VoiceKeyWalkTests.swift against the ZeusCore sources it actually uses.
# The full Linux package stops at `import Darwin` before this file is compiled, so a
# missing name in the walk (the bare `timing` at restCheck) never reached the gate.
# This script does not edit Package.swift or a workflow. It builds a temporary package.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_file=${ZEUS_WALK_TEST_FILE:-"$root/Tests/ZeusCoreTests/VoiceKeyWalkTests.swift"}
if [ ! -f "$test_file" ]; then
  echo "missing walk test: $test_file" >&2
  exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/zeus-walk-typecheck.XXXXXX")
trap 'rm -rf "$work"' EXIT

sources="
Shortcut.swift
KeyFacts.swift
VoiceKeyMachine.swift
TalkKeyPair.swift
Pointing/PointingKeyGesture.swift
Tiling/TileAction.swift
Tiling/TileKeybind.swift
Tiling/TileKeyMatcher.swift
Tiling/TileKeyList.swift
"

mkdir -p "$work/Sources/ZeusCore/Pointing" "$work/Sources/ZeusCore/Tiling" "$work/Tests/ZeusCoreTests"
for relative in $sources; do
  cp "$root/Sources/ZeusCore/$relative" "$work/Sources/ZeusCore/$relative"
done
cp "$test_file" "$work/Tests/ZeusCoreTests/VoiceKeyWalkTests.swift"

cat > "$work/Package.swift" << 'EOF'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VoiceKeyWalkTypecheck",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "ZeusCore"),
        .testTarget(name: "ZeusCoreTests", dependencies: ["ZeusCore"]),
    ]
)
EOF

# `--build-tests` typechecks the suite. Running it is not required to catch a missing name.
if ! swift build --package-path "$work" --build-tests --jobs 4 > "$work/build.log" 2>&1; then
  echo "VoiceKeyWalkTests typecheck failed" >&2
  # The useful lines are the test file diagnostics, not the stub module's noise.
  grep -E "VoiceKeyWalkTests.swift|error:" "$work/build.log" | head -80 >&2 || true
  exit 1
fi

echo "VoiceKeyWalkTests typecheck passed ($(basename "$test_file"))"
