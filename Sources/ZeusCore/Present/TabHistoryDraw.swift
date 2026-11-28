import Foundation

/// A tab with nowhere to go back or forward, drawn while Zeus says so.
///
/// The voice still says the full line. The screen builds Back then Start, or Forward then End.
/// A page that kept changing stays on its own card. A click Zeus left alone stays on its own card.
public struct TabHistoryDraw: Equatable, Sendable {
    public static let earlier = "There's no earlier page in this tab."
    public static let later = "There's no later page in this tab."

    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var way: String
    public var edge: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, way: String, edge: String) {
        self.draw = draw
        self.schedule = schedule
        self.way = way
        self.edge = edge
    }

    /// Nil unless the line is a tab with no earlier or later page.
    public static func from(line: String) -> TabHistoryDraw? {
        let flat = line.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let way: String
        let edge: String
        switch flat {
        case earlier: way = "Back"; edge = "Start"
        case later: way = "Forward"; edge = "End"
        default: return nil
        }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: way), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: edge), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TabHistoryDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), way: way, edge: edge)
    }

    /// The short line beside the bolt. The first beat names the direction. Start or End follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return way }
        return edge
    }

    /// Where the bolt sits: the ring first, then the Start or End card.
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
