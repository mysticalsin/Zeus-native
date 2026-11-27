import Foundation

/// A to-do Zeus marked done, or could not find, drawn while it says so.
///
/// The voice still says the full line. The screen builds Done or Missing, then the title.
/// A to-do that was just added stays on its own card.
public struct TodoDoneDraw: Equatable, Sendable {
    public static let doneLead = "Done: "
    public static let missLead = "I couldn't find a to-do called "

    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var lead: String
    public var title: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, lead: String, title: String) {
        self.draw = draw
        self.schedule = schedule
        self.lead = lead
        self.title = title
    }

    /// Nil unless the line marks a to-do done or says that name was not found.
    public static func from(line: String) -> TodoDoneDraw? {
        let flat = line.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.hasSuffix("."), flat.count > 1 else { return nil }
        let body = String(flat.dropLast())
        let lead: String
        let raw: String
        if body.hasPrefix(doneLead) {
            lead = "Done"
            raw = String(body.dropFirst(doneLead.count))
        } else if body.hasPrefix(missLead) {
            lead = "Missing"
            raw = String(body.dropFirst(missLead.count))
        } else {
            return nil
        }
        guard let title = clean(raw) else { return nil }
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: lead), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: title), at: 1),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TodoDoneDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), lead: lead, title: title)
    }

    /// The short line beside the bolt. The first beat says Done or Missing. The title follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return lead }
        return Self.shortLine(title)
    }

    /// Where the bolt sits: the ring first, then the title card.
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
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return trimmed.isEmpty ? "To-do" : String(trimmed.prefix(40))
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
