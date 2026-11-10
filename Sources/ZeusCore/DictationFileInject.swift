import Foundation

/// Reply text for `zeus debug dictate-file` (quiet-hours E2E). Kept in ZeusCore for unit tests.
public enum DictationFileInject {
    public struct TurnSnapshot: Equatable, Sendable {
        public var inserted: Bool
        public var resultText: String

        public init(inserted: Bool, resultText: String) {
            self.inserted = inserted
            self.resultText = resultText
        }
    }

    /// Whether text may be pasted into the app dictation started in. Only `ready` allows an
    /// automatic paste; every unknown or negative state fails closed.
    public enum TargetState: Equatable, Sendable {
        case ready
        case unavailable
        case frontmostUnavailable
        case frontmostDrift
        case focusUnavailable
        case focusDrift
    }

    /// Who an app is: its PID and bundle ID. A reused PID under another bundle is a different app.
    public struct TargetIdentity: Equatable, Sendable {
        public var pid: Int32
        public var bundleID: String?

        public init(pid: Int32, bundleID: String?) {
            self.pid = pid
            self.bundleID = bundleID
        }
    }

    /// Identity form of `targetState`: PID and bundle ID must both match (nil only matches nil).
    /// Named apart from `targetState` so an all-`nil` call there stays unambiguous.
    public static func identityState(target: TargetIdentity?, frontmost: TargetIdentity?,
                                     focus: TargetIdentity?) -> TargetState {
        guard let target else { return .unavailable }
        guard let frontmost else { return .frontmostUnavailable }
        guard frontmost == target else { return .frontmostDrift }
        guard let focus else { return .focusUnavailable }
        guard focus == target else { return .focusDrift }
        return .ready
    }

    /// PIDs of the dictation target, the frontmost app and the focused element's owner.
    public static func targetState(target: Int32?, frontmost: Int32?, focus: Int32?) -> TargetState {
        guard let target else { return .unavailable }
        guard let frontmost else { return .frontmostUnavailable }
        guard frontmost == target else { return .frontmostDrift }
        guard let focus else { return .focusUnavailable }
        guard focus == target else { return .focusDrift }
        return .ready
    }

    public static func reply(inserted: Bool, resultText: String, failureMessage: String?) -> String {
        if let failureMessage, !failureMessage.isEmpty {
            return "ERROR \(failureMessage)"
        }
        let trimmed = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inserted, !trimmed.isEmpty else { return "ERROR nothing inserted" }
        return "ok"
    }

    /// History head only when this inject added a row. Without that guard, a failed turn could
    /// still reply `ok` from the previous E2E clip (integrator FIX 02:16).
    public static func turnFromInject(historyCountBefore: Int, history: [TurnSnapshot]) -> TurnSnapshot? {
        guard history.count > historyCountBefore, let head = history.first else { return nil }
        return head
    }

    /// Matches quiet-hours E2E: ignore periods and case when checking the focused field.
    public static func fieldMatches(_ field: String?, expected: String) -> Bool {
        guard let field, !field.isEmpty else { return false }
        let cleanedField = field.lowercased().replacingOccurrences(of: ".", with: "")
        let cleanedExpected = expected.lowercased().replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedExpected.count >= 4 else { return false }
        return cleanedField.contains(cleanedExpected)
    }

    public static func replyAfterInject(historyCountBefore: Int, history: [TurnSnapshot], failureMessage: String?,
                                        fieldText: String? = nil) -> String {
        if let failureMessage, !failureMessage.isEmpty {
            return reply(inserted: false, resultText: "", failureMessage: failureMessage)
        }
        guard let turn = turnFromInject(historyCountBefore: historyCountBefore, history: history) else {
            return reply(inserted: false, resultText: "", failureMessage: nil)
        }
        let base = reply(inserted: turn.inserted, resultText: turn.resultText, failureMessage: nil)
        guard base == "ok", fieldText != nil else { return base }
        guard fieldMatches(fieldText, expected: turn.resultText) else { return "ERROR paste not verified" }
        return "ok"
    }
}
