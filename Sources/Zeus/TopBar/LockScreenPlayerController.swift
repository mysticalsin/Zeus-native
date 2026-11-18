import Foundation
import ZeusCore
#if canImport(Darwin)
import Darwin
#endif

/// The lock-screen player. The private space symbol is only probed. This build does not call it,
/// so the live path reports unavailable and creates no window.
@MainActor
final class LockScreenPlayerController {
    private let model: TopBarModel
    private let spaceAvailable: () -> Bool
    private let createSpace: () -> Bool

    init(model: TopBarModel,
         spaceAvailable: @escaping () -> Bool = { LockScreenSpaceProbe.symbolPresent() },
         createSpace: @escaping () -> Bool = { false }) {
        self.model = model
        self.spaceAvailable = spaceAvailable
        self.createSpace = createSpace
    }

    func setEnabled(_ on: Bool) {
        guard on else {
            model.lockScreenPlayer = .off
            return
        }
        let space = spaceAvailable()
        let ignored = space && createSpace()
        model.lockScreenPlayer = LockScreenPlayerGate.result(enabled: true, spaceAvailable: space, inputIgnored: ignored)
    }

    func stop() { setEnabled(false) }
}

enum LockScreenSpaceProbe {
    static func symbolPresent() -> Bool {
        #if canImport(Darwin)
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        return dlsym(handle, "CGSSpaceCreate") != nil
        #else
        return false
        #endif
    }
}

enum LockScreenPlayerText {
    static func line(_ status: LockScreenPlayerStatus) -> String {
        switch status {
        case .off: ""
        case .unavailable: "Lock screen player unavailable"
        case .shown: "On the lock screen"
        }
    }
}
