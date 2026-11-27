import Foundation

/// A Spotify request Zeus is starting, drawn while it says so.
///
/// The voice still says the full line. The screen builds Spotify, then the request,
/// or Playing when Spotify itself is resumed. A blank request is not drawn.
/// A media key stays on the media card.
public struct SpotifyPlayDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var request: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, request: String) {
        self.draw = draw
        self.schedule = schedule
        self.request = request
    }

    /// Reads the fast-action summary. Other summaries are not this card.
    public static func from(summary: String) -> SpotifyPlayDraw? {
        let flat = summary.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flat == "Play Spotify" { return plan(request: "Playing") }
        let prefix = "Spotify: "
        guard flat.hasPrefix(prefix) else { return nil }
        return plan(request: String(flat.dropFirst(prefix.count)))
    }

    /// Nil when the request is blank.
    public static func plan(request: String) -> SpotifyPlayDraw? {
        guard let request = clean(request) else { return nil }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Spotify"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: request), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return SpotifyPlayDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), request: request)
    }

    /// The short line beside the bolt. The first beat says Spotify. The request follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Spotify" }
        return Self.shortLine(request)
    }

    /// Where the bolt sits: the ring first, then the request card.
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
        return trimmed.isEmpty ? "Spotify" : String(trimmed.prefix(40))
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
