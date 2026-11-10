import Foundation

public struct ScribeCalendarSlot: Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date?

    public init(id: String, title: String, start: Date, end: Date? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
    }
}

public enum ScribePromptDecision: Equatable, Sendable {
    case none
    case upcoming(ScribeCalendarSlot)
    case callDetected(ScribeCallApp)
}

/// Pure decision for the one-tap "start listening" popup. No calendar or process IO.
public enum ScribeCallPrompt {
    /// A slot is offered from this long before it starts (inclusive).
    public static let leadWindow: TimeInterval = 120
    /// A slot is still offered until this long after it started (inclusive).
    public static let lateWindow: TimeInterval = 300

    /// Never prompts while recording. A matching calendar slot wins over a bare detected call,
    /// because it carries a title. Among eligible slots the one closest to `now` is chosen.
    public static func decide(
        now: Date,
        upcoming: [ScribeCalendarSlot],
        activeCallApp: ScribeCallApp?,
        isRecording: Bool,
        dismissedIDs: Set<String>,
        dismissedCallApps: Set<ScribeCallApp> = []
    ) -> ScribePromptDecision {
        guard !isRecording else { return .none }

        let eligible = upcoming.filter { slot in
            guard !dismissedIDs.contains(slot.id) else { return false }
            if let end = slot.end, now >= end { return false }
            let untilStart = slot.start.timeIntervalSince(now)
            return untilStart <= leadWindow && -untilStart <= lateWindow
        }
        let best = eligible.min { lhs, rhs in
            let l = abs(lhs.start.timeIntervalSince(now))
            let r = abs(rhs.start.timeIntervalSince(now))
            return l != r ? l < r : lhs.id < rhs.id
        }
        if let best { return .upcoming(best) }

        if let app = activeCallApp, !dismissedCallApps.contains(app) {
            return .callDetected(app)
        }
        return .none
    }
}
