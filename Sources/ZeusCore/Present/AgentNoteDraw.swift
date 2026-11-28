import Foundation

/// A note a named agent just kept, drawn while Zeus says so.
///
/// The voice still says the full line. The screen builds the agent's name, then the note.
/// A blank name or a blank note is not drawn. A password, a card code, or a social security
/// number is not drawn. A refusal shows only Not stored.
public struct AgentNoteDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var agent: String
    public var note: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, agent: String, note: String) {
        self.draw = draw
        self.schedule = schedule
        self.agent = agent
        self.note = note
    }

    /// True when the note must not be stored or shown.
    public static func hides(_ note: String) -> Bool {
        let lower = note.lowercased()
        return lower.contains("password") || lower.contains("cvv") || lower.contains("social security")
    }

    /// Nil when the agent or the note is blank, or the note must not be shown.
    public static func plan(agent: String, note: String) -> AgentNoteDraw? {
        guard let agent = clean(agent), let note = clean(note), !hides(note) else { return nil }
        return laidOut(agent: agent, second: note, note: note)
    }

    /// The refusal card. It carries none of the refused text. Nil when the agent name is blank.
    public static func refused(agent: String) -> AgentNoteDraw? {
        guard let agent = clean(agent) else { return nil }
        return laidOut(agent: agent, second: "Not stored", note: "")
    }

    /// The short line beside the bolt. The first beat is the agent. A kept note follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return agent }
        if note.isEmpty { return "Not stored" }
        return Self.shortLine(note)
    }

    /// Where the bolt sits: the ring first, then the note card.
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

    private static func laidOut(agent: String, second: String, note: String) -> AgentNoteDraw? {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: agent), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: second), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return AgentNoteDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), agent: agent, note: note)
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
        return trimmed.isEmpty ? "Not stored" : String(trimmed.prefix(40))
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
