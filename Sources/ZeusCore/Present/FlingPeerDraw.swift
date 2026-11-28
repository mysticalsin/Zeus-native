import Foundation

/// A spoken check of the name nearby Macs see and how many are paired, and the cards drawn while Zeus answers it.
///
/// Whether a name is set, and the paired count. The name and the Mac names stay off the card.
/// Whether Fling is on, receiving, and flick sensitivity stay their own asks. Nothing is paired or removed.
public enum FlingPeerAsk {
    public static let unread = "I can't read the paired Macs."
    public static let names = ["None", "Chosen"]

    /// True for a direct ask about the name or the paired Macs. Fling's switch is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["what", "name", "do", "nearby", "macs", "see"], ["how", "many", "macs", "are", "paired"],
             ["paired", "mac", "settings"], ["is", "a", "fling", "name", "set"],
             ["which", "macs", "are", "paired"], ["how", "is", "the", "fling", "name", "set"]:
            return true
        default:
            return false
        }
    }

    /// A known name and a count from 0 to 99 use that sentence. Anything else is unread.
    public static func line(name: String, macs: String) -> String {
        guard known(name: name, macs: macs), let count = Int(macs) else { return unread }
        return "\(nameLine(name)), and \(macLine(count))."
    }

    public static func known(name: String, macs: String) -> Bool {
        names.contains(name) && knownCount(macs)
    }

    private static func knownCount(_ value: String) -> Bool {
        guard let number = Int(value), (0...99).contains(number), String(number) == value else { return false }
        return true
    }

    private static func nameLine(_ name: String) -> String {
        name == "Chosen" ? "A name is set for nearby Macs" : "Nearby Macs see this Mac's own name"
    }

    private static func macLine(_ count: Int) -> String {
        switch count {
        case 0: "no Macs are paired"
        case 1: "1 Mac is paired"
        default: "\(count) Macs are paired"
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

public struct FlingPeerDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown value draws Can't. Otherwise Peers, then the name and the count.
    public static func plan(name: String, macs: String) -> FlingPeerDraw {
        guard FlingPeerAsk.known(name: name, macs: macs) else { return make(lines: ["Can't"]) }
        return make(lines: ["Name: \(name)", "Macs: \(macs)"])
    }

    /// The short line beside the bolt. The first beat says Peers.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Peers" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Peers"
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

    private static func make(lines: [String]) -> FlingPeerDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Peers"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return FlingPeerDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
