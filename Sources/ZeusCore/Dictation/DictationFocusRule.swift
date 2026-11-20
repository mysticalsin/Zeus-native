import Foundation

/// The frontmost app, from the workspace identity only. No focused-element read.
public struct DictationAppIdentity: Equatable, Sendable {
    public var processID: Int32
    public var bundleID: String?

    public init(processID: Int32, bundleID: String?) {
        self.processID = processID
        self.bundleID = bundleID
    }

    public func sameApp(as other: DictationAppIdentity) -> Bool {
        if processID != 0, processID == other.processID { return true }
        if let bundleID, let otherID = other.bundleID, bundleID == otherID { return true }
        return false
    }
}

/// Where a finished dictation may go.
public enum DictationInsertChoice: Equatable, Sendable {
    /// The app is still the one from key down. Type into the field read after the microphone opened.
    case postOpenField
    /// The frontmost app changed. Do not paste there.
    case copyInstead
}

public enum DictationFocusRule {
    public static func choose(keyDown: DictationAppIdentity, frontmost: DictationAppIdentity) -> DictationInsertChoice {
        keyDown.sameApp(as: frontmost) ? .postOpenField : .copyInstead
    }
}
