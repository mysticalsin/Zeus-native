import Foundation

/// A shortcut Zeus just saved or replayed, drawn while it says so.
///
/// The voice still says the full line. The screen builds Shortcut, then the phrase,
/// then up to two steps. A replay shows Done. A step that did not finish shows Not saved.
/// A blank phrase is not drawn.
public struct ShortcutDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var phrase: String
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, phrase: String, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.phrase = phrase
        self.detail = detail
    }

    /// A saved phrase and its first steps. Nil when the phrase is blank.
    public static func saved(phrase: String, steps: [String]) -> ShortcutDraw? {
        guard let phrase = clean(phrase) else { return nil }
        let shown = steps.compactMap(clean).prefix(2)
        return laidOut(cards: ["Shortcut", phrase] + shown, phrase: phrase, detail: shown.last ?? phrase)
    }

    /// The phrase was not saved. A blank phrase still shows Not saved.
    public static func notSaved(phrase: String) -> ShortcutDraw? {
        let name = clean(phrase)
        let cards = name.map { ["Shortcut", $0, "Not saved"] } ?? ["Shortcut", "Not saved"]
        return laidOut(cards: cards, phrase: name ?? "", detail: "Not saved")
    }

    /// A replay finished.
    public static func done() -> ShortcutDraw? {
        laidOut(cards: ["Shortcut", "Done"], phrase: "", detail: "Done")
    }

    /// The short line beside the bolt. The first beat says Shortcut. The latest card follows.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Shortcut" }
        let cards = cardTexts()
        guard last < cards.count else { return Self.shortLine(detail) }
        return Self.shortLine(cards[last])
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

    private func cardTexts() -> [String] {
        draw.marks.sorted { $0.at < $1.at }.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    private static func laidOut(cards: [String], phrase: String, detail: String) -> ShortcutDraw? {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
        ]
        for (index, text) in cards.enumerated() {
            let y = 160.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: index == 0 ? 180 : 920, y: y), text: text), at: index))
        }
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ShortcutDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), phrase: phrase, detail: detail)
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
        return trimmed.isEmpty ? "Shortcut" : String(trimmed.prefix(40))
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
