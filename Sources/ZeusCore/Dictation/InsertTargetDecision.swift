import Foundation

/// Where a finished dictation is inserted.
public enum InsertTarget: Equatable, Sendable {
    /// The key-down app is still frontmost, or no key-down app was captured.
    case paste
    /// Zeus is frontmost. Activate the key-down app, then paste there.
    case reactivateThenPaste
    /// Some other app is frontmost. Do not paste there.
    case copyOnly
}

public enum InsertTargetDecision {
    /// `ownPid` is this process. A frontmost Zeus window is not a third app.
    /// A key-down identity with pid 0 or no bundle id was not captured, so the caller keeps the earlier insert path.
    public static func decide(keyDown: DictationAppIdentity, frontmost: DictationAppIdentity, ownPid: Int32) -> InsertTarget {
        if keyDown.processID == 0 || keyDown.bundleID?.isEmpty != false {
            return .paste
        }
        if ownPid != 0, frontmost.processID == ownPid {
            return .reactivateThenPaste
        }
        if keyDown.sameApp(as: frontmost) {
            return .paste
        }
        return .copyOnly
    }
}
