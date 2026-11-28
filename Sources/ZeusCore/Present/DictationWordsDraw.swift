import Foundation

/// A spoken count of words dictated today, and the cards drawn while Zeus answers it.
///
/// The voice says the count. The words themselves stay off the card. Focus rounds stay
/// on their own card.
public enum DictationWordsAsk {
    public static let none = "No words dictated today."

    /// True for a direct ask about words dictated today. Reading one aloud is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["words", "today"], ["dictation", "words"], ["dictation", "words", "today"],
             ["how", "many", "words", "today"], ["how", "many", "dictation", "words"],
             ["how", "many", "dictation", "words", "today"],
             ["how", "many", "words", "did", "i", "dictate"],
             ["how", "many", "words", "did", "i", "dictate", "today"],
             ["how", "many", "words", "have", "i", "dictated"],
             ["how", "many", "words", "have", "i", "dictated", "today"]:
            return true
        default:
            return false
        }
    }

    /// Nil when the count is below one.
    public static func line(count: Int) -> String? {
        guard count >= 1 else { return nil }
        if count == 1 { return "You dictated 1 word today." }
        return "You dictated \(count) words today."
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

public struct DictationWordsDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var count: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, count: String) {
        self.draw = draw
        self.schedule = schedule
        self.count = count
    }

    /// Nil when the count is below one. Cards are Words, the number, then Today.
    public static func plan(count: Int) -> DictationWordsDraw? {
        guard DictationWordsAsk.line(count: count) != nil else { return nil }
        return make(lines: ["\(count)", "Today"], count: "\(count)")
    }

    public static func none() -> DictationWordsDraw { make(lines: ["None"], count: "") }

    /// The short line beside the bolt. The first beat says Words.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Words" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Words"
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

    private static func make(lines: [String], count: String) -> DictationWordsDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Words"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return DictationWordsDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), count: count)
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
