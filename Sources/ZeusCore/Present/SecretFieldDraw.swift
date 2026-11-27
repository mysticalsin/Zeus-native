import Foundation

/// A password or payment field Zeus will not type, drawn while it says so.
///
/// The voice still says the full line. The screen builds Secret, then You.
/// Typing Zeus left undone stays on its own card. A finished walkthrough stays on its own card.
public struct SecretFieldDraw: Equatable, Sendable {
    /// What is spoken after the ten-word clip, and the shorter fallback.
    public static let lines = [
        "That's a password or payment field, so I left it.",
        "That's a password or payment field. Please type it yourself.",
        "That's a password or payment field, so I left it for you. Type it yourself and tell me when to carry on.",
    ]

    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Nil unless the line is Zeus leaving a password or payment field.
    public static func from(line: String) -> SecretFieldDraw? {
        let flat = line.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard lines.contains(flat) else { return nil }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Secret"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: "You"), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return SecretFieldDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
    }

    /// The short line beside the bolt. The first beat says Secret. You follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Secret" }
        return "You"
    }

    /// Where the bolt sits: the ring first, then the You card.
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
