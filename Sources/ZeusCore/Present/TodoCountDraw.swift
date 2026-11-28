import Foundation

/// How many to-dos are still open, drawn while Zeus says it.
///
/// The voice says the count. The screen builds To-dos, then the count, then Open or the overdue count.
/// Adding a to-do, and the day's brief, stay on their own cards.
public enum TodoCountAsk {
    public static let none = "You have no to-dos."
    public static let done = "All to-dos are done."

    /// True for a direct ask about how many to-dos are left. Adding one is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "many", "to", "dos"], ["how", "many", "todos"],
             ["how", "many", "to", "dos", "do", "i", "have"], ["how", "many", "todos", "do", "i", "have"],
             ["how", "many", "to", "dos", "left"], ["how", "many", "todos", "left"],
             ["how", "many", "tasks", "left"], ["how", "many", "tasks", "do", "i", "have"],
             ["how", "many", "open", "to", "dos"], ["how", "many", "open", "todos"]:
            return true
        default:
            return false
        }
    }

    /// Nil when the open count is below one, or overdue does not fit inside it.
    public static func line(open: Int, overdue: Int) -> String? {
        guard open >= 1, overdue >= 0, overdue <= open else { return nil }
        let left = open == 1 ? "You have 1 to-do left" : "You have \(open) to-dos left"
        if overdue == 0 { return "\(left)." }
        if overdue == 1 { return "\(left), 1 overdue." }
        return "\(left), \(overdue) overdue."
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

public struct TodoCountDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var count: String
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, count: String, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.count = count
        self.detail = detail
    }

    /// Nil when the open count is below one, or overdue does not fit inside it.
    public static func plan(open: Int, overdue: Int) -> TodoCountDraw? {
        guard TodoCountAsk.line(open: open, overdue: overdue) != nil else { return nil }
        let count = "\(open)"
        let detail = overdue == 0 ? "Open" : (overdue == 1 ? "1 overdue" : "\(overdue) overdue")
        return make(lines: [count, detail], count: count, detail: detail)
    }

    public static func none() -> TodoCountDraw { make(lines: ["None"], count: "", detail: "") }
    public static func clear() -> TodoCountDraw { make(lines: ["Done"], count: "", detail: "") }

    /// The short line beside the bolt. The first beat says To-dos.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "To-dos" }
        if last >= 2, !detail.isEmpty { return detail }
        if !count.isEmpty { return count }
        return detailWord
    }

    private var detailWord: String {
        for mark in draw.marks {
            if case .card(_, let text) = mark.shape, text != "To-dos" { return text }
        }
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

    private static func make(lines: [String], count: String, detail: String) -> TodoCountDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "To-dos"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TodoCountDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), count: count, detail: detail)
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
