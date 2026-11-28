import Foundation

/// A spoken check of the nearby-Mac strip, and the cards drawn while Zeus answers it.
///
/// Fling is off, blocked, or looking. Nearby is how many Macs are showing, and how many of those are paired.
/// Saved pairs, the name, and file names stay their own asks. Nothing is turned on or sent.
public enum FlingNearbyAsk {
    public static let unread = "I can't read the nearby Macs."
    public static let states = ["Off", "Denied", "Looking"]

    /// True for a direct ask about Macs that are nearby now. Saved pairs are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "many", "macs", "are", "nearby"], ["is", "fling", "looking"],
             ["is", "local", "network", "off", "for", "fling"], ["fling", "nearby", "settings"],
             ["are", "any", "macs", "nearby"], ["how", "is", "the", "nearby", "strip", "set"]:
            return true
        default:
            return false
        }
    }

    /// A state and counts that can happen together use that sentence. Anything else is unread.
    public static func line(state: String, nearby: String, ready: String) -> String {
        guard let seen = knownCount(state: state, nearby: nearby, ready: ready) else { return unread }
        switch state {
        case "Off": return "Fling is off, and no nearby Macs are shown."
        case "Denied": return "Local Network is off for Fling, and no nearby Macs are shown."
        default:
            if seen.nearby == 0 { return "Fling is looking, and no Macs are nearby." }
            return "Fling is looking, \(seenWord(seen.nearby)), and \(readyWord(seen.nearby, seen.ready))."
        }
    }

    public static func known(state: String, nearby: String, ready: String) -> Bool {
        knownCount(state: state, nearby: nearby, ready: ready) != nil
    }

    private static func knownCount(state: String, nearby: String, ready: String) -> (nearby: Int, ready: Int)? {
        guard states.contains(state), let seen = count(nearby), let paired = count(ready), paired <= seen else { return nil }
        if state != "Looking", seen != 0 || paired != 0 { return nil }
        return (seen, paired)
    }

    private static func count(_ value: String) -> Int? {
        guard let number = Int(value), (0...99).contains(number), String(number) == value else { return nil }
        return number
    }

    private static func seenWord(_ count: Int) -> String {
        switch count {
        case 1: "1 Mac is nearby"
        default: "\(count) Macs are nearby"
        }
    }

    private static func readyWord(_ seen: Int, _ paired: Int) -> String {
        if seen == 0 { return "none are paired" }
        if paired == 0 { return seen == 1 ? "it is not paired" : "none are paired" }
        if paired == seen { return seen == 1 ? "it is paired" : "all \(seen) are paired" }
        return paired == 1 ? "1 is paired" : "\(paired) are paired"
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

public struct FlingNearbyDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// A count that cannot happen draws Can't. Otherwise Nearby, then the state and the two counts.
    public static func plan(state: String, nearby: String, ready: String) -> FlingNearbyDraw {
        guard FlingNearbyAsk.known(state: state, nearby: nearby, ready: ready) else { return make(lines: ["Can't"]) }
        return make(lines: ["State: \(state)", "Nearby: \(nearby)", "Paired: \(ready)"])
    }

    /// The short line beside the bolt. The first beat says Nearby.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Nearby" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Nearby"
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

    private static func make(lines: [String]) -> FlingNearbyDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Nearby"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return FlingNearbyDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
