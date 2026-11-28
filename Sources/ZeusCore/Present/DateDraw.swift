import Foundation

/// The calendar date, drawn while Zeus says it.
///
/// The voice says the full line. The screen builds Date, then the weekday, then the day.
/// The wall clock, a city, and the countdown stay on their own cards.
public enum DateAsk {
    /// True for a direct ask about today's date. A meeting day is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["date"], ["the", "date"], ["current", "date"], ["today", "date"],
             ["what", "is", "the", "date"], ["what", "is", "the", "date", "today"],
             ["what", "is", "today", "date"], ["what", "is", "today"],
             ["what", "day", "is", "it"], ["what", "day", "is", "it", "today"],
             ["what", "day", "is", "today"],
             ["tell", "me", "the", "date"], ["tell", "me", "today", "date"]:
            return true
        default:
            return false
        }
    }

    /// "Wednesday" and "4 November 2026". The calendar stays Gregorian.
    public static func parts(now: Date, timeZone: TimeZone) -> (weekday: String, date: String) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: now)
        formatter.dateFormat = "d MMMM yyyy"
        return (weekday, formatter.string(from: now))
    }

    /// Nil when the weekday or the date is blank.
    public static func line(weekday: String, date: String) -> String? {
        guard let weekday = shown(weekday), let date = shown(date) else { return nil }
        return "It's \(weekday), \(date)."
    }

    static func shown(_ raw: String) -> String? {
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
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { token -> String in
            var word = String(token)
            if word.hasSuffix("'s"), word.count > 3 { word = String(word.dropLast(2)) }
            return word.replacingOccurrences(of: "'", with: "")
        }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct DateDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var weekday: String
    public var date: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, weekday: String, date: String) {
        self.draw = draw
        self.schedule = schedule
        self.weekday = weekday
        self.date = date
    }

    /// Nil when the weekday or the date is blank.
    public static func plan(weekday: String, date: String) -> DateDraw? {
        guard let weekday = DateAsk.shown(weekday), let date = DateAsk.shown(date) else { return nil }
        return make(weekday: weekday, date: date)
    }

    /// The short line beside the bolt. The first beat says Date.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Date" }
        if last >= 2 { return Self.shortLine(date) }
        return Self.shortLine(weekday)
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

    private static func make(weekday: String, date: String) -> DateDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Date"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: weekday), at: 1),
            .init(shape: .card(origin: .init(x: 920, y: 250), text: date), at: 2),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return DateDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), weekday: weekday, date: date)
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
