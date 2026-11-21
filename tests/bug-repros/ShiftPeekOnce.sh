#!/bin/sh
# Red repro on codex/integration-20261111. ShiftPeekGate stays revealed after
# Shift goes up unless release() is called, and Sources/Zeus never calls
# shiftGate.release. A second hold therefore cannot fire. Exits 1 while present.
set -eu
cd "$(CDPATH= cd -P "$(dirname "$0")/../.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
    if [ -x "$HOME/swift-toolchain/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swiftc" ]; then
        PATH="$HOME/swift-toolchain/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH"
        export PATH
    fi
fi
command -v swiftc >/dev/null 2>&1 || { echo "swiftc is required" >&2; exit 2; }
if git grep -n "shiftGate.release" HEAD -- Sources/Zeus >/dev/null 2>&1; then
    echo "the app now calls shiftGate.release"
    exit 0
fi
echo "Sources/Zeus never calls shiftGate.release"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# ShiftPeekGate is self-contained. The rest of the file needs macOS-only neighbours.
{
    echo 'import Foundation'
    sed -n '226,244p' Sources/ZeusCore/TopBar/NotchLights.swift
} > "$work/ShiftPeekGate.swift"
cat > "$work/main.swift" << 'EOF'
import Foundation
@main
struct Main {
    static func main() {
        var gate = ShiftPeekGate()
        let start = Date(timeIntervalSince1970: 1_000)
        gate.shift(down: true, at: start)
        guard gate.fire(at: start.addingTimeInterval(0.5)) else {
            print("first hold did not fire")
            exit(2)
        }
        gate.shift(down: false, at: start.addingTimeInterval(0.6))
        gate.shift(down: true, at: start.addingTimeInterval(1))
        if gate.fire(at: start.addingTimeInterval(1.6)) {
            print("second hold fired")
            exit(0)
        }
        print("BUG: second Shift hold does not fire after release without ShiftPeekGate.release()")
        exit(1)
    }
}
EOF
swiftc -parse-as-library -o "$work/repro" "$work/ShiftPeekGate.swift" "$work/main.swift"
"$work/repro"
