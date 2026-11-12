import Foundation

public struct ScribeCalendarSlot: Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date?
    /// Display names of the invitees. Never email addresses: `ScribeAttendeeNames.clean` drops those.
    public var attendeeNames: [String]
    /// The event carries a call link (Teams, Zoom, Meet, Webex...). Only the meeting-start detector reads it.
    public var hasCallLink: Bool

    public init(id: String, title: String, start: Date, end: Date? = nil, attendeeNames: [String] = [],
                hasCallLink: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendeeNames = ScribeAttendeeNames.clean(attendeeNames)
        self.hasCallLink = hasCallLink
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

/// Names of the people on a calendar invite, as display names only.
public enum ScribeAttendeeNames {
    /// Trimmed, deduplicated, in order. An entry that is an email address (or holds an `@`) is dropped: an
    /// address never reaches a transcript, a suggestion or a saved file.
    public static func clean(_ names: [String], limit: Int = 50) -> [String] {
        var seen: Set<String> = []
        var kept: [String] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("@"), !name.contains("://"), name.count <= 80 else { continue }
            guard seen.insert(key(name)).inserted else { continue }
            kept.append(name)
            if kept.count >= limit { break }
        }
        return kept
    }

    /// Case, accent and spacing differences do not make two names two people.
    public static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
