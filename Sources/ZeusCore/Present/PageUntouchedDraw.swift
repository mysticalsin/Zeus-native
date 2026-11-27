import Foundation

/// Chrome left a page untouched, drawn while Zeus says so.
///
/// The voice still says the full line. The screen names what changed, then that nothing was touched.
/// A page that kept changing under a browser agent stays on its own card.
public struct PageUntouchedDraw: Equatable, Sendable {
    public static let unknown = "Chrome couldn't identify the page. Nothing was changed."
    public static let navigated = "The approved page navigated. Nothing was changed."
    public static let privateWindow = "Zeus doesn't read private windows. Nothing was changed."
    public static let closed = "The approved tab was closed. Nothing was changed."
    public static let reloaded = "The approved page reloaded. Nothing was changed."
    public static let switched = "The active tab or approved page changed. Nothing was changed."
    public static let gone = "The selected tab is no longer available."

    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var way: String
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, way: String, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.way = way
        self.detail = detail
    }

    /// Nil unless the line is a page Zeus left untouched.
    public static func from(line: String) -> PageUntouchedDraw? {
        let flat = line.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let way: String
        let detail: String
        switch flat {
        case unknown: way = "Chrome"; detail = "Untouched"
        case navigated: way = "Page"; detail = "Moved"
        case privateWindow: way = "Private"; detail = "Off"
        case closed: way = "Tab"; detail = "Closed"
        case reloaded: way = "Page"; detail = "Reloaded"
        case switched: way = "Tab"; detail = "Switched"
        case gone: way = "Tab"; detail = "Gone"
        default: return nil
        }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: way), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: detail), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PageUntouchedDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), way: way, detail: detail)
    }

    /// The short line beside the bolt. The first beat names what changed. The reason follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return way }
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
