import Foundation

/// A routine just saved, drawn on the talk surface while Zeus says it was saved.
///
/// The voice still says the full line. The screen builds it: a ring and the word
/// Routine, then the name, then when it runs. A blank name is not drawn.
public struct RoutineSavedDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String
    public var when: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String, when: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
        self.when = when
    }

    /// "Weekdays at 8 AM" or "Every day at 3 PM". Hour 0 is 12 AM. Hour 12 is 12 PM.
    public static func whenLine(daily: Bool, hour: Int) -> String {
        let hour = min(max(hour, 0), 23)
        let clock = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        let days = daily ? "Every day" : "Weekdays"
        return "\(days) at \(clock) \(suffix)"
    }

    /// Nil when the name is blank.
    public static func plan(name: String, when: String) -> RoutineSavedDraw? {
        guard let name = clean(name) else { return nil }
        let when = clean(when) ?? ""
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Routine"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: name), at: 1),
        ]
        if !when.isEmpty {
            marks.append(.init(shape: .card(origin: .init(x: 920, y: 250), text: when), at: 2))
        }
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return RoutineSavedDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name, when: when)
    }

    /// The short line beside the bolt. The first beat says Routine, then the name, then the time.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last else { return "Routine" }
        if last >= 2, !when.isEmpty { return Self.shortLine(when) }
        if last >= 1 { return Self.shortLine(name) }
        return "Routine"
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
        return trimmed.isEmpty ? "Routine" : String(trimmed.prefix(40))
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
