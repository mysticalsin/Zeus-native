import Foundation

/// An action that did not finish, drawn while Zeus says so.
///
/// The voice still says the full line. The screen builds Didn't open, No response,
/// or Couldn't open, then the name. Opening a project that misses also names the project.
/// A blank name is not drawn. An answer failure stays on its own card.
public struct ActionMissDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var label: String
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, label: String, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.label = label
        self.name = name
    }

    /// Reads the spoken problem. Other lines are not this card.
    public static func from(line: String) -> ActionMissDraw? {
        let flat = line.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let openPair = " didn't open "
        if let range = flat.range(of: openPair) {
            let app = String(flat[..<range.lowerBound])
            var project = String(flat[range.upperBound...])
            if project.hasSuffix(".") { project.removeLast() }
            return plan(label: "Didn't open", name: app, extra: project)
        }
        if flat.hasSuffix(" didn't open.") {
            return plan(label: "Didn't open", name: String(flat.dropLast(" didn't open.".count)), extra: nil)
        }
        if flat.hasSuffix(" didn't respond.") {
            return plan(label: "No response", name: String(flat.dropLast(" didn't respond.".count)), extra: nil)
        }
        let couldNot = "I couldn't open "
        if flat.hasPrefix(couldNot), flat.hasSuffix(".") {
            return plan(label: "Couldn't open", name: String(flat.dropFirst(couldNot.count).dropLast()), extra: nil)
        }
        return nil
    }

    /// Nil when the label or the name is blank. A blank extra is dropped.
    public static func plan(label: String, name: String, extra: String?) -> ActionMissDraw? {
        guard let label = clean(label), let name = clean(name) else { return nil }
        let extra = extra.flatMap(clean)
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: label), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: name), at: 1),
        ]
        if let extra {
            marks.append(.init(shape: .card(origin: .init(x: 920, y: 250), text: extra), at: 2))
        }
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ActionMissDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), label: label, name: name)
    }

    /// The short line beside the bolt. The first beat is the failure. The name follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return label }
        if last >= 2, let extra = extraText { return Self.shortLine(extra) }
        return Self.shortLine(name)
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

    private var extraText: String? {
        for mark in draw.marks where mark.at == 2 {
            if case .card(_, let text) = mark.shape { return text }
        }
        return nil
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
        return trimmed.isEmpty ? "Missed" : String(trimmed.prefix(40))
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
