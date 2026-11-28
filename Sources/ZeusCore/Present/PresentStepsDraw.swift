import Foundation

/// A present card built on screen while Zeus says each step.
///
/// The voice still says every step. The screen shows the ring and up to five
/// step lines. A card with no words is not drawn.
public struct PresentStepsDraw: Equatable, Sendable {
    /// Ring plus five cards is the talk-draw mark limit.
    public static let maxLines = 5

    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var lines: [String]

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, lines: [String]) {
        self.draw = draw
        self.schedule = schedule
        self.lines = lines
    }

    /// Nil when every line is blank. Extra lines past the mark limit stay spoken only.
    public static func plan(lines raw: [String]) -> PresentStepsDraw? {
        let lines = raw.compactMap(clean).prefix(maxLines)
        guard let first = lines.first else { return nil }
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: first), at: 0),
        ]
        for (offset, line) in lines.dropFirst().enumerated() {
            let y = 180.0 + Double(offset) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: line), at: offset + 1))
        }
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PresentStepsDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), lines: Array(lines))
    }

    /// The short line beside the bolt. The first beat is the first step. Later beats follow.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, lines.indices.contains(last) else { return lines.first ?? "Here" }
        return Self.shortLine(lines[last])
    }

    /// Where the bolt sits: the ring first, then the newest step.
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
        return trimmed.isEmpty ? "Here" : String(trimmed.prefix(40))
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
