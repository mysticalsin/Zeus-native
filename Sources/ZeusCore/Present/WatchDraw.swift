import Foundation

/// A watch Zeus just started, drawn while it says it will watch.
///
/// The voice still says the full line. The screen builds Watching, then what is being
/// watched, then whether it should appear, go away, or the build should finish.
/// A blank label is not drawn. Stopping shows only Stopped. The shell test is never drawn.
public struct WatchDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var label: String
    public var waiting: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, label: String, waiting: String) {
        self.draw = draw
        self.schedule = schedule
        self.label = label
        self.waiting = waiting
    }

    /// Nil when the label or the wait is blank.
    public static func plan(label: String, waiting: String) -> WatchDraw? {
        guard let label = clean(label), let waiting = clean(waiting) else { return nil }
        return make(head: "Watching", label: label, waiting: waiting)
    }

    /// Stopping every watch. No target is named.
    public static func stopped() -> WatchDraw {
        make(head: "Stopped", label: "", waiting: "")
    }

    /// The short line beside the bolt. The first beat is Watching or Stopped. The wait follows the label.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last else { return head }
        if last >= 2, !waiting.isEmpty { return Self.shortLine(waiting) }
        if last >= 1, !label.isEmpty { return Self.shortLine(label) }
        return head
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

    private var head: String {
        for mark in draw.marks {
            if case .card(_, let text) = mark.shape, mark.at == 0 { return text }
        }
        return "Watching"
    }

    private static func make(head: String, label: String, waiting: String) -> WatchDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: head), at: 0),
        ]
        if !label.isEmpty {
            marks.append(.init(shape: .card(origin: .init(x: 920, y: 180), text: label), at: 1))
        }
        if !waiting.isEmpty {
            marks.append(.init(shape: .card(origin: .init(x: 920, y: 250), text: waiting), at: 2))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return WatchDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), label: label, waiting: waiting)
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
        return trimmed.isEmpty ? "Watching" : String(trimmed.prefix(40))
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
