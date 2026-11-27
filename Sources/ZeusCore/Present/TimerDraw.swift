import Foundation

/// A focus timer drawn on the talk surface while Zeus says it is set.
///
/// The voice still says the full line. The screen builds Timer, then the length,
/// in the same words as the spoken line. A negative length is not drawn.
/// Cancelling shows only Cancelled.
public struct TimerDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var length: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, length: String) {
        self.draw = draw
        self.schedule = schedule
        self.length = length
    }

    /// "5 minutes", "1 hour 30 minutes", "45 seconds". A negative length is "0 seconds".
    public static func duration(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if rest > 0 { parts.append(rest == 1 ? "1 second" : "\(rest) seconds") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    /// Nil when the length is negative.
    public static func plan(seconds: Int) -> TimerDraw? {
        guard seconds >= 0 else { return nil }
        let length = duration(seconds)
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Timer"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: length), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TimerDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), length: length)
    }

    /// Cancelling. No length is shown.
    public static func cancelled() -> TimerDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Cancelled"), at: 0),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        return TimerDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: [0]), length: "")
    }

    /// The short line beside the bolt. The first beat says Timer or Cancelled. The length follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1, !length.isEmpty else {
            return length.isEmpty ? "Cancelled" : "Timer"
        }
        return Self.shortLine(length)
    }

    /// Where the bolt sits: the ring first, then the length card.
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
        return "Timer"
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
