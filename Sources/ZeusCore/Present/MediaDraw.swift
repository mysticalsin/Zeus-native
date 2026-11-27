import Foundation

/// A media key Zeus just sent, drawn while it says what the player will do.
///
/// The voice still says the full line. The screen builds Media, then Playing, Paused,
/// Next, Previous, or Play or pause. Anything else is not drawn.
public struct MediaDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var action: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, action: String) {
        self.draw = draw
        self.schedule = schedule
        self.action = action
    }

    /// Nil unless `action` is play, pause, next, previous, or toggle.
    public static func plan(action: String) -> MediaDraw? {
        let word: String
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "play": word = "Playing"
        case "pause": word = "Paused"
        case "next": word = "Next"
        case "previous": word = "Previous"
        case "toggle": word = "Play or pause"
        default: return nil
        }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Media"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: word), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return MediaDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), action: word)
    }

    /// The short line beside the bolt. The first beat says Media. The action follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Media" }
        return action
    }

    /// Where the bolt sits: the ring first, then the action card.
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
