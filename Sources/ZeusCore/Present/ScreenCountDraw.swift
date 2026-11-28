import Foundation

/// A spoken screen count, and the cards drawn while Zeus answers it.
///
/// The voice says how many displays there are and the name of the one in use.
/// Tiling stays on its own card.
public enum ScreenCountAsk {
    public static let unseen = "I can't see a screen."

    /// True for a direct ask about the displays. Tiling is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "many", "screens"], ["how", "many", "displays"], ["how", "many", "monitors"],
             ["which", "screen"], ["which", "display"], ["which", "monitor"],
             ["what", "screen", "is", "this"], ["what", "display", "is", "this"],
             ["what", "is", "this", "screen"], ["what", "is", "this", "display"]:
            return true
        default:
            return false
        }
    }

    /// The name that fits on the card. Blank is nil.
    public static func cardName(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        return String(flat.prefix(TalkDraw.maxTextCharacters))
    }

    /// Nil when the count is below one.
    public static func line(count: Int, name: String) -> String? {
        guard count >= 1 else { return nil }
        let name = cardName(name)
        if count == 1 {
            guard let name else { return "You have 1 screen." }
            return "You have 1 screen, \(name)."
        }
        guard let name else { return "You have \(count) screens." }
        return "You have \(count) screens. This one is \(name)."
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct ScreenCountDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// Nil when the count is below one. One screen draws the name, then 1. Several draw the count, then the name.
    public static func plan(count: Int, name: String) -> ScreenCountDraw? {
        guard ScreenCountAsk.line(count: count, name: name) != nil else { return nil }
        let name = ScreenCountAsk.cardName(name) ?? ""
        if count == 1 {
            let lines = name.isEmpty ? ["1"] : [name, "1"]
            return make(lines: lines, name: name)
        }
        let left = "\(count)"
        let lines = name.isEmpty ? [left] : [left, name]
        return make(lines: lines, name: name)
    }

    public static func unseen() -> ScreenCountDraw { make(lines: ["Can't"], name: "") }

    /// The short line beside the bolt. The first beat says Screens.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Screens" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Screens"
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

    private static func make(lines: [String], name: String) -> ScreenCountDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Screens"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ScreenCountDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
