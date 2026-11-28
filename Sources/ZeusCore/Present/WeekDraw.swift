import Foundation

/// A spoken week ask, and the cards drawn while Zeus answers it.
///
/// The voice says the week and how many events it holds. The screen builds Week, then the
/// number, then the count. The agenda, and the next event, stay on their own cards.
public enum WeekAsk {
    public static let access = "I need Calendar access to read the week."

    /// True for a direct ask about this week. The agenda and the next event are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["this", "week"], ["my", "week"], ["the", "week"],
             ["what", "is", "my", "week"], ["how", "is", "my", "week"], ["what", "is", "this", "week"],
             ["how", "busy", "is", "my", "week"], ["how", "busy", "is", "this", "week"],
             ["what", "is", "on", "this", "week"], ["what", "is", "on", "my", "week"]:
            return true
        default:
            return false
        }
    }

    /// The week-of-year and the month name. Nil when the week number is not 1...53.
    public static func parts(now: Date, calendar: Calendar) -> (week: Int, month: String)? {
        let week = calendar.component(.weekOfYear, from: now)
        guard (1...53).contains(week) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: now).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !month.isEmpty else { return nil }
        return (week, month)
    }

    /// Events whose start falls in the week that contains `now`.
    public static func count(starts: [Date], now: Date, calendar: Calendar) -> Int {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return starts.filter { interval.contains($0) }.count
    }

    /// Nil when the week or the month is unusable, or the count is negative.
    public static func line(week: Int, month: String, count: Int) -> String? {
        guard (1...53).contains(week), count >= 0 else { return nil }
        let month = month.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !month.isEmpty else { return nil }
        if count == 0 { return "Week \(week) of \(month) is clear." }
        if count == 1 { return "Week \(week) of \(month). You have 1 event." }
        return "Week \(week) of \(month). You have \(count) events."
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct WeekDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var number: String
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, number: String, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.number = number
        self.detail = detail
    }

    /// Nil when the week or the month is unusable, or the count is negative.
    public static func plan(week: Int, month: String, count: Int) -> WeekDraw? {
        guard WeekAsk.line(week: week, month: month, count: count) != nil else { return nil }
        let number = "\(week)"
        let detail = count == 0 ? "Clear" : (count == 1 ? "1 event" : "\(count) events")
        return make(lines: [number, detail], number: number, detail: detail)
    }

    public static func access() -> WeekDraw { make(lines: ["Access"], number: "", detail: "") }

    /// The short line beside the bolt. The first beat says Week.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Week" }
        if last >= 2, !detail.isEmpty { return detail }
        if !number.isEmpty { return number }
        return detailWord
    }

    private var detailWord: String {
        for mark in draw.marks {
            if case .card(_, let text) = mark.shape, text != "Week" { return text }
        }
        return "Access"
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

    private static func make(lines: [String], number: String, detail: String) -> WeekDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Week"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return WeekDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), number: number, detail: detail)
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
