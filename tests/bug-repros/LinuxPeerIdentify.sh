#!/bin/sh
# Red repro on codex/integration-20261111. PeerCheck.identify returns nil on
# this Linux host for a connected socket pair, so the same-user policy cannot
# accept the owner. Exits 1 while the non-Darwin branch stays nil.
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
cp Sources/ZeusCore/PeerCredentials.swift Sources/ZeusCore/PeerSigning.swift Sources/ZeusCore/ZeusPaths.swift "$work/"
cat > "$work/main.swift" << 'EOF'
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@main
struct Main {
    static func main() {
        var pair = [Int32](repeating: 0, count: 2)
        #if canImport(Darwin)
        let stream = SOCK_STREAM
        #else
        let stream = Int32(SOCK_STREAM.rawValue)
        #endif
        guard socketpair(AF_UNIX, stream, 0, &pair) == 0 else {
            print("socketpair failed")
            exit(2)
        }
        defer { close(pair[0]); close(pair[1]) }
        let peer = PeerCheck.identify(fd: pair[0])
        print("identify=\(String(describing: peer))")
        if peer == nil {
            print("BUG: connected peer has no identity")
            exit(1)
        }
    }
}
EOF
swiftc -parse-as-library -o "$work/repro" \
    "$work/ZeusPaths.swift" "$work/PeerSigning.swift" "$work/PeerCredentials.swift" "$work/main.swift"
"$work/repro"
