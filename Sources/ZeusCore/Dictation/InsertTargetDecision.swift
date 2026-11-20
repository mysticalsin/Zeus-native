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

public struct InsertPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case paste, reactivate, copyOnly }
    public var action: Action
    public var app: DictationAppIdentity?

    public init(action: Action, app: DictationAppIdentity?) {
        self.action = action
        self.app = app
    }
}

/// Which app a deliver or a correction acts on.
public enum InsertRoute: Equatable, Sendable {
    case paste
    case copyOnly
    /// Bring this app forward, then paste there.
    case reactivate(DictationAppIdentity)
}

public enum InsertTargetDecision {
    /// `ownPid` is this process. A frontmost Zeus window is not a third app.
    /// A key-down identity with pid 0 or no bundle id was not captured, so the caller keeps the earlier insert path.
    public static func decide(keyDown: DictationAppIdentity, frontmost: DictationAppIdentity, ownPid: Int32) -> InsertTarget {
        switch route(keyDown: keyDown, postOpen: nil, frontmost: frontmost, ownPid: ownPid) {
        case .paste: return .paste
        case .copyOnly: return .copyOnly
        case .reactivate: return .reactivateThenPaste
        }
    }

    /// `postOpen` is the app read after the microphone opens. When Zeus is frontmost, the app to
    /// bring back is the key-down app, not `postOpen`.
    public static func route(keyDown: DictationAppIdentity, postOpen: DictationAppIdentity?, frontmost: DictationAppIdentity, ownPid: Int32) -> InsertRoute {
        let captured = keyDown.processID != 0 && keyDown.bundleID?.isEmpty == false
        if !captured {
            if let postOpen, !postOpen.sameApp(as: frontmost) {
                return .reactivate(postOpen)
            }
            return .paste
        }
        if ownPid != 0, frontmost.processID == ownPid {
            return .reactivate(keyDown)
        }
        if keyDown.sameApp(as: frontmost) {
            return .paste
        }
        return .copyOnly
    }

    /// What `deliver()` and `deliverCorrection()` execute. A paste uses the key-down app.
    public static func plan(keyDown: DictationAppIdentity, postOpen: DictationAppIdentity?, frontmost: DictationAppIdentity, ownPid: Int32) -> InsertPlan {
        let captured = keyDown.processID != 0 && keyDown.bundleID?.isEmpty == false
        switch route(keyDown: keyDown, postOpen: postOpen, frontmost: frontmost, ownPid: ownPid) {
        case .paste:
            return InsertPlan(action: .paste, app: captured ? keyDown : (postOpen ?? keyDown))
        case .copyOnly:
            return InsertPlan(action: .copyOnly, app: nil)
        case .reactivate(let id):
            return InsertPlan(action: .reactivate, app: id)
        }
    }

    public static func correctionPlan(keyDown: DictationAppIdentity, postOpen: DictationAppIdentity?, frontmost: DictationAppIdentity, ownPid: Int32) -> InsertPlan {
        plan(keyDown: keyDown, postOpen: postOpen, frontmost: frontmost, ownPid: ownPid)
    }

    /// The branch `deliver()` runs. Copy-only stays copy-only.
    public static func deliverEffect(_ route: InsertRoute) -> InsertRoute { route }

    /// The branch `deliverCorrection()` runs. A re-activate is not dropped.
    public static func correctionEffect(_ route: InsertRoute) -> InsertRoute {
        switch route {
        case .reactivate(let id): return .reactivate(id)
        case .paste: return .paste
        case .copyOnly: return .copyOnly
        }
    }
}
