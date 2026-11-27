import Foundation

/// A Beamer command Zeus could not carry out, drawn while it says why.
///
/// The voice still says the full line. The screen builds Beamer, then Not running,
/// Missing, Nothing, or No reply. A Beamer command that ran stays on its own card.
public struct BeamerMissDraw: Equatable, Sendable {
    public static let notRunning = "Beamer isn't running. Say start Beamer first."
    public static let missing = "Beamer isn't installed. Settings › Beamer can install it."
    public static let nothing = "Beamer has nothing to bring back."
    public static let noReply = "Beamer didn't answer."

    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.detail = detail
    }

    /// Nil unless the line is a Beamer command Zeus could not carry out.
    public static func from(line: String) -> BeamerMissDraw? {
        let flat = line.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail: String
        switch flat {
        case notRunning: detail = "Not running"
        case missing: detail = "Missing"
        case nothing: detail = "Nothing"
        case noReply: detail = "No reply"
        default: return nil
        }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Beamer"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: detail), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return BeamerMissDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), detail: detail)
    }

    /// The short line beside the bolt. The first beat says Beamer. The reason follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Beamer" }
        return detail
    }

    /// Where the bolt sits: the ring first, then the reason card.
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
