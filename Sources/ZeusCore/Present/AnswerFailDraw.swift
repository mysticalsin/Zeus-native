import Foundation

/// A spoken answer failure, drawn while Zeus says why.
///
/// The voice still says the full line. The screen builds AI, then Quota, Sign in,
/// No answer, Offline, or Failed. Any other sentence is not this card.
public struct AnswerFailDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.detail = detail
    }

    /// Nil unless the line is one of the spoken answer failures.
    public static func from(message: String) -> AnswerFailDraw? {
        let flat = message.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail: String
        switch flat {
        case "Every AI is out of quota; instant commands still work.": detail = "Quota"
        case "That AI isn't signed in; check Settings.": detail = "Sign in"
        case "No AI answered in time; try again.": detail = "No answer"
        case "I couldn't reach Claude; check your connection.": detail = "Offline"
        case "The AI failed; try again.": detail = "Failed"
        default: return nil
        }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "AI"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: detail), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return AnswerFailDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), detail: detail)
    }

    /// The short line beside the bolt. The first beat says AI. The reason follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "AI" }
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
