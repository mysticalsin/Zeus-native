import Foundation

/// Joining a meeting, drawn while Zeus says so.
///
/// The voice says the full line. The screen builds Meeting, then the title, then Zoom,
/// Meet, or Teams when the link names one. A reminder stays on its own card.
public enum MeetingAsk {
    public static let none = "There's no meeting to join."

    /// True for a direct ask to join the next meeting. Opening an app is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["join", "my", "next", "meeting"], ["join", "the", "next", "meeting"],
             ["join", "next", "meeting"], ["join", "my", "meeting"], ["join", "the", "meeting"]:
            return true
        default:
            return false
        }
    }

    /// Nil when the title is blank. A missing place stays out of the sentence.
    public static func line(title: String, place: String) -> String? {
        guard let title = trimmed(title) else { return nil }
        if let place = trimmed(place) { return "Joining \(title) on \(place)." }
        return "Joining \(title)."
    }

    /// Zoom, Meet, Teams, or the host. An empty host is an empty place.
    public static func place(of url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if host.contains("zoom.us") { return "Zoom" }
        if host.contains("meet.google") { return "Meet" }
        if host.contains("teams.") { return "Teams" }
        if host.contains("webex.com") { return "Webex" }
        if host.contains("whereby.com") { return "Whereby" }
        if host.contains("around.co") { return "Around" }
        if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
        return host
    }

    private static func words(in text: String) -> [String] {
        let folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        let raw = folded.split { !$0.isLetter && $0 != "'" }.map { token -> String in
            var word = String(token)
            if word.hasSuffix("'s"), word.count > 3 { word = String(word.dropLast(2)) }
            return word.replacingOccurrences(of: "'", with: "")
        }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "zeus", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }

    private static func trimmed(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct MeetingDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var title: String
    public var place: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, title: String, place: String) {
        self.draw = draw
        self.schedule = schedule
        self.title = title
        self.place = place
    }

    /// Nil when the title is blank. A blank place is left off.
    public static func plan(title: String, place: String) -> MeetingDraw? {
        guard let title = clean(title) else { return nil }
        let place = clean(place) ?? ""
        return make(cards: [title, place.isEmpty ? nil : place].compactMap { $0 }, title: title, place: place)
    }

    public static func none() -> MeetingDraw {
        make(cards: ["None"], title: "", place: "")
    }

    /// The short line beside the bolt. The first beat says Meeting.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Meeting" }
        if last >= 2, !place.isEmpty { return Self.shortLine(place) }
        if !title.isEmpty { return Self.shortLine(title) }
        return "None"
    }

    /// Where the bolt sits: the ring first, then the newest card.
    public func guideBolt(at elapsed: TimeInterval) -> TalkDraw.Point? {
        let shown = Set(schedule.revealed(at: elapsed))
        let marks = draw.marks.filter { shown.contains($0.at) }
        guard let beat = marks.map(\.at).max() else { return nil }
        let placed = marks.filter { $0.at == beat }.compactMap { mark -> (Int, TalkDraw.Point)? in
            guard let point = Self.anchor(of: mark) else { return nil }
            return (Self.preference(mark), point)
        }
        return placed.min { $0.0 < $1.0 }?.1
    }

    private static func make(cards: [String], title: String, place: String) -> MeetingDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Meeting"), at: 0),
        ]
        for (index, text) in cards.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return MeetingDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), title: title, place: place)
    }

    private static func clean(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(TalkDraw.maxTextCharacters))
    }

    private static func shortLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > 40 { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? String(raw.prefix(40)) : line
    }

    private static func preference(_ mark: TalkDraw.Mark) -> Int {
        switch mark.shape {
        case .ring: return 0
        case .arrow: return 1
        case .ink: return 2
        case .card: return 3
        }
    }

    private static func anchor(of mark: TalkDraw.Mark) -> TalkDraw.Point? {
        switch mark.shape {
        case .ring(let center, let radius):
            guard radius.isFinite, radius > 0, center.x.isFinite, center.y.isFinite else { return nil }
            return center
        case .arrow(let from, let to):
            let point = TalkDraw.Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            guard point.x.isFinite, point.y.isFinite else { return nil }
            return point
        case .ink(let points):
            return points.last
        case .card(let origin, _):
            guard origin.x.isFinite, origin.y.isFinite else { return nil }
            return origin
        }
    }
}
