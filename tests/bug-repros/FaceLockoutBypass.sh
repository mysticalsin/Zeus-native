#!/bin/sh
# Red repro for the face-approval lockout bypass on PR #48 (1ba23ae66127).
# Builds the real FaceVerificationMachine and shows that fallbackResult(succeeded: true)
# for the action that is already open clears a lockout and grants approval.
# Exits 1 while the bug is present. Not wired into Package.swift or CI.
set -eu
cd "$(CDPATH= cd -P "$(dirname "$0")/../.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
    if [ -x "$HOME/swift-toolchain/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swiftc" ]; then
        PATH="$HOME/swift-toolchain/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH"
        export PATH
    fi
fi
command -v swiftc >/dev/null 2>&1 || { echo "swiftc is required" >&2; exit 2; }
SHA=1ba23ae66127
git cat-file -e "$SHA^{commit}" || { echo "missing commit $SHA (fetch zeus-bot/settings-faceid)" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
show() { git show "$SHA:$1" > "$work/$(basename "$1")"; }
show Sources/ZeusCore/Settings/GlassSettingsMetrics.swift
show Sources/ZeusCore/FacePresence/SpoofCues.swift
show Sources/ZeusCore/FacePresence/FaceMatch.swift
show Sources/ZeusCore/FacePresence/FacePresenceStatus.swift
show Sources/ZeusCore/FacePresence/FacePresenceMachine.swift
show Sources/ZeusCore/Settings/Sections/FaceID/FaceVerificationTypes.swift
show Sources/ZeusCore/Settings/Sections/FaceID/FaceVerificationMatch.swift
show Sources/ZeusCore/Settings/Sections/FaceID/FaceVerificationMachine.swift
mkdir -p "$work/shim"
cat > "$work/shim/CoreGraphics.swift" << 'EOF'
public typealias CGFloat = Double
EOF
swiftc -parse-as-library -emit-module -emit-library -module-name CoreGraphics \
    -emit-module-path "$work/CoreGraphics.swiftmodule" -o "$work/libCoreGraphics.so" \
    "$work/shim/CoreGraphics.swift"
cat > "$work/main.swift" << 'EOF'
import Foundation
@main
struct Main {
    static func main() {
        var machine = FaceVerificationMachine()
        _ = machine.handle(.enable(enrolled: true, camera: .authorized, uptime: 1))
        let limit = FaceVerificationPolicy.failureLimit
        for index in 0..<(limit - 1) {
            let action = ApprovalAction(id: "warmup", nonce: "n\(index)")
            _ = machine.handle(.beginApproval(action, uptime: 10 + Double(index)))
            _ = machine.handle(.capture(.noFace, uptime: 10 + Double(index)))
        }
        let open = ApprovalAction(id: "pay", nonce: "open-nonce")
        _ = machine.handle(.beginApproval(open, uptime: 100))
        _ = machine.handle(.capture(.noFace, uptime: 100))
        guard machine.phase == .lockedOut, machine.grant == nil else {
            print("setup did not lock: \(machine.phase)")
            exit(2)
        }
        _ = machine.handle(.fallbackResult(succeeded: true, action: open, uptime: 101))
        if machine.grant != nil || machine.phase != .lockedOut {
            print("BUG phase=\(machine.phase) grant=\(String(describing: machine.grant)) failures=\(machine.failures)")
            exit(1)
        }
        print("lockout held")
    }
}
EOF
swiftc -parse-as-library -I "$work" -L "$work" -lCoreGraphics -o "$work/repro" \
    "$work/GlassSettingsMetrics.swift" "$work/SpoofCues.swift" "$work/FaceMatch.swift" \
    "$work/FacePresenceStatus.swift" "$work/FacePresenceMachine.swift" \
    "$work/FaceVerificationTypes.swift" "$work/FaceVerificationMatch.swift" \
    "$work/FaceVerificationMachine.swift" "$work/main.swift"
LD_LIBRARY_PATH="$work" "$work/repro"
