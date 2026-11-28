import Foundation

/// A browser agent that stopped at its step limit, drawn while Zeus says so.
///
/// The voice still says the full line. The screen builds Steps, then the count.
/// A page that kept changing stays on its own card. A blank count is not drawn.
public struct StepLimitDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var count: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, count: String) {
        self.draw = draw
        self.schedule = schedule
        self.count = count
    }

    /// Nil unless the line is the step-limit stop, with a count.
    public static func from(line: String) -> StepLimitDraw? {
        let flat = line.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = "I stopped after "
        let tail = " steps without finishing. Tell me how to go on."
        guard flat.hasPrefix(lead), flat.hasSuffix(tail), flat.count > lead.count + tail.count else { return nil }
        let raw = String(flat.dropFirst(lead.count).dropLast(tail.count))
        guard !raw.isEmpty, raw.allSatisfy(\.isNumber) else { return nil }
        let count = String(raw.prefix(TalkDraw.maxTextCharacters))
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Steps"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: count), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return StepLimitDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), count: count)
    }

    /// The short line beside the bolt. The first beat says Steps. The count follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Steps" }
        return count
    }

    /// Where the bolt sits: the ring first, then the count card.
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
