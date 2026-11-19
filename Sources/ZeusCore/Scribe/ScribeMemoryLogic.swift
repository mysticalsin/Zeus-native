import Foundation

/// Pure helpers for the Scribe Memory window: how meetings group by date, who spoke how much, and the
/// one-line outcome of each meeting. No views, no clocks: the window and the tests read the same numbers.

public enum ScribeMemoryBucket: Int, CaseIterable, Comparable, Sendable {
    case today
    case thisWeek
    case earlier

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This week"
        case .earlier: return "Earlier"
        }
    }
}

public struct ScribeMemorySection<ID: Hashable & Sendable>: Equatable, Sendable {
    public let bucket: ScribeMemoryBucket
    /// Newest first.
    public let ids: [ID]

    public init(bucket: ScribeMemoryBucket, ids: [ID]) {
        self.bucket = bucket
        self.ids = ids
    }
}

public enum ScribeMemoryGrouping {
    /// A date later than `now` (a clock that moved back) counts as today, so a meeting never disappears.
    public static func bucket(for date: Date, now: Date, calendar: Calendar = .current) -> ScribeMemoryBucket {
        if date >= now || calendar.isDate(date, inSameDayAs: now) { return .today }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), date >= week.start { return .thisWeek }
        return .earlier
    }

    /// Meetings grouped Today, This week, Earlier. Each group is newest first (ties keep the input order),
    /// and a group with no meetings is left out.
    public static func sections<ID: Hashable & Sendable>(
        _ entries: [(id: ID, date: Date)], now: Date, calendar: Calendar = .current
    ) -> [ScribeMemorySection<ID>] {
        var grouped: [ScribeMemoryBucket: [(index: Int, id: ID, date: Date)]] = [:]
        for (index, entry) in entries.enumerated() {
            let bucket = bucket(for: entry.date, now: now, calendar: calendar)
            grouped[bucket, default: []].append((index, entry.id, entry.date))
        }
        var result: [ScribeMemorySection<ID>] = []
        for bucket in ScribeMemoryBucket.allCases {
            guard let items = grouped[bucket], !items.isEmpty else { continue }
            let ordered = items.sorted { lhs, rhs in
                lhs.date != rhs.date ? lhs.date > rhs.date : lhs.index < rhs.index
            }
            result.append(ScribeMemorySection(bucket: bucket, ids: ordered.map(\.id)))
        }
        return result
    }
}

public enum ScribeInitials {
    /// First letter of the first and the last word, upper case: "Marie Dubois" is "MD", "Marie" is "M".
    /// Words that do not start with a letter or digit (a "(Guest)" tag's bracket) are skipped. "?" when empty.
    public static func of(_ name: String) -> String {
        var letters: [Character] = []
        for word in name.split(whereSeparator: \.isWhitespace) {
            let trimmed = word.drop { !($0.isLetter || $0.isNumber) }
            if let first = trimmed.first { letters.append(first) }
        }
        guard let first = letters.first else { return "?" }
        guard letters.count > 1, let last = letters.last else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }
}

public struct ScribeMemoryPerson: Equatable, Sendable {
    public let speaker: ScribeSpeaker
    public let name: String
    public let initials: String
    public let talkSeconds: TimeInterval
    /// 0...1
    public let share: Double
    /// Whole percent of the talking, for display.
    public let percent: Int
}

public enum ScribeMemoryPeople {
    /// Everyone who spoke, most talk first (ties keep the order they first spoke in).
    public static func people(segments: [ScribeTranscriptSegment]) -> [ScribeMemoryPerson] {
        let stats = ScribeSpeakerStats(segments: segments)
        let ordered = stats.speakers.enumerated().sorted { lhs, rhs in
            lhs.element.share != rhs.element.share ? lhs.element.share > rhs.element.share : lhs.offset < rhs.offset
        }
        return ordered.map { _, entry in
            ScribeMemoryPerson(
                speaker: entry.speaker,
                name: entry.speaker.displayName,
                initials: ScribeInitials.of(entry.speaker.displayName),
                talkSeconds: entry.talkSeconds,
                share: entry.share,
                percent: Int((entry.share * 100).rounded())
            )
        }
    }
}

public enum ScribeMemoryOutcome {
    /// The text on one line: runs of white space collapse, and a long text is cut with an ellipsis.
    public static func clip(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard limit > 1, flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// The first action item that is not ticked yet.
    public static func firstOpenAction(_ notes: ScribeMeetingNotes) -> String? {
        notes.actionItems.first { !$0.done && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { clip($0.text, limit: 120) }
    }

    /// One line for the list: the first decision, else the first open action, else the start of the summary.
    public static func line(_ notes: ScribeMeetingNotes, limit: Int = 90) -> String {
        if let decision = notes.decisions.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return clip(decision, limit: limit)
        }
        if let action = firstOpenAction(notes) { return clip(action, limit: limit) }
        let summary = clip(notes.summary, limit: limit)
        return summary.isEmpty ? "No summary." : summary
    }

    /// "Under a minute", "42 min", "1 h 5 min", "2 h".
    public static func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = seconds.isFinite ? Int((max(0, seconds) / 60).rounded()) : 0
        if minutes < 1 { return "Under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

/// What the Memory search looks through for one meeting.
public struct ScribeMemoryFields: Equatable, Sendable {
    public var title: String
    public var summary: String
    public var decisions: [String]
    public var actionItems: [String]
    public var people: [String]
    public var transcript: String

    public init(title: String, summary: String, decisions: [String], actionItems: [String],
                people: [String], transcript: String) {
        self.title = title
        self.summary = summary
        self.decisions = decisions
        self.actionItems = actionItems
        self.people = people
        self.transcript = transcript
    }
}

/// Search text plus person filters. Every word must be found, and every chosen person must have spoken or been
/// named in the meeting. Case, accents and spacing do not matter.
public struct ScribeMemoryQuery: Equatable, Sendable {
    public var text: String
    public var people: [String]

    public init(text: String = "", people: [String] = []) {
        self.text = text
        self.people = people
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && people.isEmpty
    }

    public func matches(_ fields: ScribeMemoryFields) -> Bool {
        if !people.isEmpty {
            let present = Set(fields.people.map { ScribeAttendeeNames.key($0) })
            for person in people where !present.contains(ScribeAttendeeNames.key(person)) { return false }
        }
        let words = ScribeAttendeeNames.key(text).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = ScribeAttendeeNames.key(
            ([fields.title, fields.summary] + fields.decisions + fields.actionItems + fields.people + [fields.transcript])
                .joined(separator: " ")
        )
        return words.allSatisfy { haystack.contains($0) }
    }

    /// The people to offer as filters: everyone across the meetings, once each, in the order first seen.
    public static func filterChoices(_ peopleByMeeting: [[String]]) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for list in peopleByMeeting {
            for name in list where seen.insert(ScribeAttendeeNames.key(name)).inserted { names.append(name) }
        }
        return names
    }
}
