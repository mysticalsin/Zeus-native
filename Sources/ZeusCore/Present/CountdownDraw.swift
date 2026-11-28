import Foundation

/// The Home countdown, drawn while Zeus says how many days are left.
///
/// The voice says the full line. The screen builds Countdown, then the title, then the count.
/// A timer stays on its own card. With no date set, the second card is None.
public enum CountdownAsk {
    public static let none = "Pick a countdown in Settings."

    /// True for a direct ask about the Home countdown. A timer and a date in the sentence are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["countdown"], ["the", "countdown"], ["my", "countdown"],
             ["what", "countdown"], ["what", "is", "the", "countdown"], ["what", "the", "countdown"],
             ["how", "many", "days", "left"], ["how", "many", "days", "are", "left"],
             ["how", "many", "days", "to", "go"], ["days", "left"]:
            return true
        default:
            return false
        }
    }

    /// Whole days from today's start to the target's start. Negative once the day has passed.
    public static func days(to target: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
    }

    /// "Today", "1 day", "12 days", "1 day ago", or "3 days ago".
    public static func lengthLine(_ days: Int) -> String {
        switch days {
        case 0: return "Today"
        case 1: return "1 day"
        case let count where count > 1: return "\(count) days"
        case -1: return "1 day ago"
        default: return "\(abs(days)) days ago"
        }
    }

    /// Nil is not used. A blank title is spoken as "The countdown".
    public static func line(title: String, days: Int) -> String {
        let name = place(title) ?? "The countdown"
        switch days {
        case 0: return "\(name) is today."
        case 1: return "\(name) is in 1 day."
        case let count where count > 1: return "\(name) is in \(count) days."
        case -1: return "\(name) was 1 day ago."
        default: return "\(name) was \(abs(days)) days ago."
        }
    }

    static func place(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(TalkDraw.maxTextCharacters))
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct CountdownDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var title: String
    public var length: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, title: String, length: String) {
        self.draw = draw
        self.schedule = schedule
        self.title = title
        self.length = length
    }

    /// The title is left off when it is blank. The count is always drawn.
    public static func plan(title: String, days: Int) -> CountdownDraw {
        let length = CountdownAsk.lengthLine(days)
        let title = CountdownAsk.place(title) ?? ""
        let lines = title.isEmpty ? [length] : [title, length]
        return make(lines: lines, title: title, length: length)
    }

    public static func none() -> CountdownDraw {
        make(lines: ["None"], title: "", length: "")
    }

    /// The short line beside the bolt. The first beat says Countdown.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Countdown" }
        if last >= 2, !length.isEmpty { return length }
        if !title.isEmpty { return Self.shortLine(title) }
        return length.isEmpty ? "None" : length
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

    private static func make(lines: [String], title: String, length: String) -> CountdownDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Countdown"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return CountdownDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), title: title, length: length)
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
