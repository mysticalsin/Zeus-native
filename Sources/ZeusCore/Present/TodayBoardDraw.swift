import Foundation

/// Today's brief drawn on the talk surface while the full brief is spoken.
///
/// The voice still says the sentences. The screen builds them: a ring and the word
/// Today, then the calendar line, then the to-do line, then a meeting or the weather
/// when there is one.
public struct TodayBoardDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var lines: [String]

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, lines: [String]) {
        self.draw = draw
        self.schedule = schedule
        self.lines = lines
    }

    /// The calendar card. No events is "Clear". One event keeps its name. More than one is a count.
    public static func eventLine(count: Int, first: String?) -> String {
        let count = max(count, 0)
        if count == 0 { return "Clear" }
        if count == 1, let first = clean(first ?? "") { return first }
        return "\(count) events"
    }

    /// The to-do card. Nothing due is "No to-dos". An overdue count replaces the list.
    public static func todoLine(count: Int, overdue: Int, first: String?) -> String {
        let count = max(count, 0)
        if count == 0 { return "No to-dos" }
        if overdue > 0 { return "\(overdue) overdue" }
        if count == 1, let first = clean(first ?? "") { return first }
        return "\(count) to-dos"
    }

    /// Nil when there is no meeting. One meeting keeps its name.
    public static func meetingLine(count: Int, first: String?) -> String? {
        let count = max(count, 0)
        if count == 0 { return nil }
        if count == 1, let first = clean(first ?? "") { return first }
        return "\(count) meetings"
    }

    public static func plan(events: String, todos: String, meetings: String?, weather: String?) -> TodayBoardDraw {
        var lines = [clean(events) ?? "Clear", clean(todos) ?? "No to-dos"]
        if let meetings = clean(meetings ?? "") { lines.append(meetings) }
        if let weather = clean(weather ?? "") { lines.append(weather) }
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Today"), at: 0),
        ]
        for (index, line) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: line), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TodayBoardDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), lines: lines)
    }

    /// The short line beside the bolt. The first beat says Today. Later beats name the card.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Today" }
        let index = last - 1
        guard lines.indices.contains(index) else { return "Today" }
        return Self.shortLine(lines[index])
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
        if !line.isEmpty { return line }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Today" : String(trimmed.prefix(40))
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
