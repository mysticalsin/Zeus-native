import Foundation

/// A spoken check of the quick to-do key, and the cards drawn while Zeus answers it.
///
/// The key is one of the six shortcut titles. It either matches the agent picker or it does not.
/// The agent picker and the to-do list stay their own asks. Nothing is registered or changed.
public enum QuickTodoAsk {
    public static let unread = "I can't read the quick to-do key."
    /// The same titles as the Quick to-do menu.
    public static let keys = ["Off", "⌃⌥ Space", "⌥⌘ Z", "⌃⌘ Z", "⌃⌥ T", "⌥⌘ T"]
    public static let matches = ["Clear", "Same"]

    /// True for a direct ask about the quick to-do key. The agent picker is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["what", "is", "the", "quick", "to", "do", "key"], ["how", "is", "the", "quick", "to", "do", "set"],
             ["quick", "to", "do", "settings"], ["is", "the", "quick", "to", "do", "key", "off"],
             ["does", "the", "quick", "to", "do", "key", "clash"], ["which", "quick", "to", "do", "key"]:
            return true
        default:
            return false
        }
    }

    /// A known key and a match that can happen with it use that sentence. Anything else is unread.
    public static func line(key: String, match: String) -> String {
        guard known(key: key, match: match) else { return unread }
        let clash = match == "Same" ? "it is the same as the agent picker" : "it does not match the agent picker"
        return "\(keyWord(key)), and \(clash)."
    }

    public static func known(key: String, match: String) -> Bool {
        guard keys.contains(key), matches.contains(match) else { return false }
        return key != "Off" || match == "Clear"
    }

    private static func keyWord(_ key: String) -> String {
        switch key {
        case "Off": "The quick to-do key is off"
        case "⌃⌥ Space": "The quick to-do key is Control, Option, and Space"
        case "⌥⌘ Z": "The quick to-do key is Option, Command, and Z"
        case "⌃⌘ Z": "The quick to-do key is Control, Command, and Z"
        case "⌃⌥ T": "The quick to-do key is Control, Option, and T"
        default: "The quick to-do key is Option, Command, and T"
        }
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
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

public struct QuickTodoDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// A key that cannot have that match draws Can't. Otherwise Quick, then the key and the match.
    public static func plan(key: String, match: String) -> QuickTodoDraw {
        guard QuickTodoAsk.known(key: key, match: match) else { return make(lines: ["Can't"]) }
        return make(lines: ["Key: \(key)", "Match: \(match)"])
    }

    /// The short line beside the bolt. The first beat says Quick.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Quick" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Quick"
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

    private static func make(lines: [String]) -> QuickTodoDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Quick"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return QuickTodoDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
