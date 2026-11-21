#!/bin/sh
# Red repro on codex/integration-20261111: ZeusVersion(parsing:) turns
# "2.0.0-rc1" into 2.0.0. Exits 1 while that parse remains.
set -eu
cd "$(CDPATH= cd -P "$(dirname "$0")/../.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
    if [ -x "$HOME/swift-toolchain/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swiftc" ]; then
        PATH="$HOME/swift-toolchain/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH"
        export PATH
    fi
fi
command -v swiftc >/dev/null 2>&1 || { echo "swiftc is required" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
{
    echo '#if canImport(FoundationNetworking)'
    echo 'import FoundationNetworking'
    echo '#endif'
    cat Sources/ZeusCore/Updates/UpdateAvailability.swift
} > "$work/UpdateAvailability.swift"
cat > "$work/main.swift" << 'EOF'
import Foundation
@main
struct Main {
    static func main() {
        let parsed = ZeusVersion(parsing: "2.0.0-rc1")
        let stable = ZeusVersion(major: 2, minor: 0, patch: 0)
        print("parsed=\(String(describing: parsed))")
        if parsed == stable {
            print("BUG: pre-release string parsed as 2.0.0")
            exit(1)
        }
    }
}
EOF
swiftc -parse-as-library -o "$work/repro" "$work/UpdateAvailability.swift" "$work/main.swift"
"$work/repro"
