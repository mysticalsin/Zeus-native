import Foundation

/// A spoken check of Memory learning, and the cards drawn while Zeus answers it.
///
/// Learning is on or paused. Forgotten is how many meetings stay out, from 0 to 999.
/// Page names, meeting names, and the second brain stay off this ask. Nothing is learned or reset.
public enum MemoryLearnAsk {
    public static let unread = "I can't read memory learning."
    public static let states = ["On", "Paused"]

    /// True for a direct ask about Memory learning. The second brain is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["is", "memory", "learning", "on"], ["how", "is", "memory", "learning", "set"],
             ["memory", "learning", "settings"], ["is", "memory", "learning", "paused"],
             ["how", "many", "meetings", "are", "forgotten"], ["which", "memory", "learning"]:
            return true
        default:
            return false
        }
    }

    /// A known state and a count from 0 to 999 use that sentence. Anything else is unread.
    public static func line(state: String, forgotten: String) -> String {
        guard let count = knownCount(state: state, forgotten: forgotten) else { return unread }
        return "Memory learning is \(word(state)), and \(forgottenWord(count))."
    }

    public static func known(state: String, forgotten: String) -> Bool {
        knownCount(state: state, forgotten: forgotten) != nil
    }

    private static func knownCount(state: String, forgotten: String) -> Int? {
        guard states.contains(state), let count = Int(forgotten), (0...999).contains(count), String(count) == forgotten else { return nil }
        return count
    }

    private static func word(_ state: String) -> String { state == "On" ? "on" : "paused" }

    private static func forgottenWord(_ count: Int) -> String {
        switch count {
        case 0: "no meetings are forgotten"
        case 1: "1 meeting is forgotten"
        default: "\(count) meetings are forgotten"
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

public struct MemoryLearnDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown state draws Can't. Otherwise Learn, then the state and the forgotten count.
    public static func plan(state: String, forgotten: String) -> MemoryLearnDraw {
        guard MemoryLearnAsk.known(state: state, forgotten: forgotten) else { return make(lines: ["Can't"]) }
        return make(lines: ["State: \(state)", "Forgotten: \(forgotten)"])
    }

    /// The short line beside the bolt. The first beat says Learn.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Learn" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Learn"
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

    private static func make(lines: [String]) -> MemoryLearnDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Learn"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return MemoryLearnDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
