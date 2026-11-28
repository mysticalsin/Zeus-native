import Foundation

/// A spoken check of the pages on the open notch, and the cards drawn while Zeus answers it.
///
/// Home is always first. The Home cards and the notch lights stay their own asks.
public enum TopBarTabsAsk {
    public static let unread = "I can't read the top bar tabs."
    /// The same titles as `TopBarTab.title`.
    public static let words = ["Home", "Agents", "Music", "Calendar", "To-do", "Weather", "Clipboard", "Shelf", "Focus", "Murmure", "Prompter", "Chat", "Today", "Alerts", "Reminders", "Usage", "Insomnia", "Continuity", "Waves", "Tiling", "Polyglot", "Record", "Scribe"]

    /// True for a direct ask about the top bar tabs. Home cards are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "tabs", "are", "on"], ["which", "tabs", "are", "showing"],
             ["what", "is", "on", "the", "bar"], ["how", "is", "the", "top", "bar"],
             ["top", "bar", "tabs"], ["which", "pages", "are", "on", "the", "notch"]:
            return true
        default:
            return false
        }
    }

    /// A list that starts with Home uses that sentence. Anything else is unread.
    public static func line(words: [String]) -> String {
        guard words.first == "Home", words.allSatisfy({ Self.words.contains($0) }) else { return unread }
        if words.count <= 4 { return "The bar shows \(list(words))." }
        return "The bar shows \(words.count) tabs, starting \(list(Array(words.prefix(4))))."
    }

    private static func list(_ words: [String]) -> String {
        switch words.count {
        case 0: return ""
        case 1: return words[0]
        case 2: return "\(words[0]) and \(words[1])"
        default:
            let head = words.dropLast().joined(separator: ", ")
            return "\(head), and \(words[words.count - 1])"
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

public struct TopBarTabsDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var names: [String]

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, names: [String]) {
        self.draw = draw
        self.schedule = schedule
        self.names = names
    }

    /// A list that does not start with Home draws Can't. Otherwise Tabs, then up to four names.
    public static func plan(words: [String]) -> TopBarTabsDraw {
        guard words.first == "Home", words.allSatisfy({ TopBarTabsAsk.words.contains($0) }) else {
            return make(lines: ["Can't"], names: [])
        }
        return make(lines: Array(words.prefix(4)), names: words)
    }

    /// The short line beside the bolt. The first beat says Tabs.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Tabs" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Tabs"
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

    private static func make(lines: [String], names: [String]) -> TopBarTabsDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Tabs"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TopBarTabsDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), names: names)
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
