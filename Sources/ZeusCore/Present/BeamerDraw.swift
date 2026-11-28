import Foundation

/// A Beamer command Zeus is running, drawn while it says so.
///
/// The voice still says the full line. The screen builds Beamer, then Start, Open,
/// Pause, Resume, This Mac, the machine, or Not paired. A blank machine is not drawn.
/// Switching to an app stays on the app card.
public struct BeamerDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.detail = detail
    }

    /// Reads the fast-action summary. Other summaries are not this card.
    public static func from(summary: String) -> BeamerDraw? {
        let flat = summary.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch flat {
        case "Start Beamer": return plan(detail: "Start")
        case "Open Beamer": return plan(detail: "Open")
        case "Pause Beamer": return plan(detail: "Pause")
        case "Resume Beamer": return plan(detail: "Resume")
        case "Input back to this Mac": return plan(detail: "This Mac")
        case "iPad": return plan(detail: "Not paired")
        default:
            let prefix = "Switch to "
            guard flat.hasPrefix(prefix) else { return nil }
            return plan(detail: String(flat.dropFirst(prefix.count)))
        }
    }

    /// Nil when the detail is blank.
    public static func plan(detail: String) -> BeamerDraw? {
        guard let detail = clean(detail) else { return nil }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Beamer"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: detail), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return BeamerDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), detail: detail)
    }

    /// The short line beside the bolt. The first beat says Beamer. The detail follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Beamer" }
        return Self.shortLine(detail)
    }

    /// Where the bolt sits: the ring first, then the detail card.
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
        return trimmed.isEmpty ? "Beamer" : String(trimmed.prefix(40))
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
