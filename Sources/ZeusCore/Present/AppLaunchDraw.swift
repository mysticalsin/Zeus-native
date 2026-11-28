import Foundation

/// An app Zeus is opening or switching to, drawn while it says so.
///
/// The voice still says the full line. The screen builds App, then the name, then Open or Switch.
/// A site summary such as "Open example.com" is not an app and is not drawn.
public struct AppLaunchDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String
    public var switching: Bool

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String, switching: Bool) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
        self.switching = switching
    }

    /// Reads the fast-action summary. "Open Safari" and "Switch to Music" draw. A dotted host does not.
    public static func from(summary: String) -> AppLaunchDraw? {
        if summary.hasPrefix("Switch to ") {
            return plan(name: String(summary.dropFirst("Switch to ".count)), switching: true)
        }
        if summary.hasPrefix("Open ") {
            let name = String(summary.dropFirst("Open ".count))
            if name.contains(".") { return nil }
            return plan(name: name, switching: false)
        }
        return nil
    }

    /// Nil when the name is blank.
    public static func plan(name: String, switching: Bool) -> AppLaunchDraw? {
        guard let name = clean(name), !name.contains(".") else { return nil }
        let state = switching ? "Switch" : "Open"
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "App"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: name), at: 1),
            .init(shape: .card(origin: .init(x: 920, y: 250), text: state), at: 2),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return AppLaunchDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name, switching: switching)
    }

    /// The short line beside the bolt. The first beat says App, then the name, then Open or Switch.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last else { return "App" }
        if last >= 2 { return switching ? "Switch" : "Open" }
        if last >= 1 { return Self.shortLine(name) }
        return "App"
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
        return trimmed.isEmpty ? "App" : String(trimmed.prefix(40))
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
