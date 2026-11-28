import Foundation

/// A spoken check of what makes the browser agent ask, and the cards drawn while Zeus answers it.
///
/// How many extra words always ask, and that buying, sending, deleting, and posting always ask.
/// The extra words stay off the card. Starting a web task stays its own ask.
public enum AskWordsAsk {
    public static let unread = "I can't read what always asks."
    public static let builtIns = ["Always"]

    /// True for a direct ask about the extra words. The browser, the step limit, and a running task are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["what", "always", "asks"], ["which", "words", "always", "ask"],
             ["how", "is", "always", "ask", "set"], ["browser", "ask", "settings"],
             ["do", "extra", "words", "always", "ask"], ["what", "makes", "the", "browser", "agent", "ask"]:
            return true
        default:
            return false
        }
    }

    /// A count from 0 to 99 and the built-in always-ask use that sentence. Anything else is unread.
    public static func line(extra: String, builtIn: String) -> String {
        guard known(extra: extra, builtIn: builtIn), let count = Int(extra) else { return unread }
        return "\(extraWord(count)), and buying, sending, deleting, and posting always ask."
    }

    public static func known(extra: String, builtIn: String) -> Bool {
        knownCount(extra) && builtIns.contains(builtIn)
    }

    /// Comma-separated words, blanks dropped. The words themselves are not returned.
    public static func extraCount(_ stored: String) -> Int {
        stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.count
    }

    private static func knownCount(_ value: String) -> Bool {
        guard let number = Int(value), (0...99).contains(number), String(number) == value else { return false }
        return true
    }

    private static func extraWord(_ count: Int) -> String {
        switch count {
        case 0: "No extra words always ask"
        case 1: "1 extra word always asks"
        default: "\(count) extra words always ask"
        }
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct AskWordsDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Ask, then the extra count and the built-in list.
    public static func plan(extra: String, builtIn: String) -> AskWordsDraw {
        guard AskWordsAsk.known(extra: extra, builtIn: builtIn) else { return make(lines: ["Can't"]) }
        return make(lines: ["Extra: \(extra)", "Built-in: \(builtIn)"])
    }

    /// The short line beside the bolt. The first beat says Ask.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Ask" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Ask"
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

    private static func make(lines: [String]) -> AskWordsDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Ask"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return AskWordsDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
