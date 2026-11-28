import Foundation

/// A spoken check of Fling receiving, and the cards drawn while Zeus answers it.
///
/// Accept, closed-notch receive, links, papers, and the arrival glow.
/// Whether Fling is on, and where arrivals are saved, stay their own ask.
public enum ReceiveSetupAsk {
    public static let unread = "I can't read Fling receiving."
    /// The same order as the receiving switches. Where arrivals go stays on the Fling ask.
    public static let order = ["Accept", "Closed", "Links", "Papers", "Glow"]
    /// The screen shows at most this many switches. The line still counts the rest.
    public static let shown = 4

    /// True for a direct ask about Fling receiving. The files on the Shelf are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "receiving", "set"], ["which", "fling", "receiving"],
             ["receiving", "settings"], ["does", "fling", "receive", "while", "closed"],
             ["are", "fling", "papers", "on"], ["which", "arrival", "switches"]:
            return true
        default:
            return false
        }
    }

    /// Known names in card order use that sentence. An empty list is off. Anything else is unread.
    public static func line(words: [String]) -> String {
        guard canonical(words) else { return unread }
        if words.isEmpty { return "Fling receiving is off." }
        if words.count <= shown { return "Fling receiving has \(list(words)) on." }
        return "Fling receiving has \(words.count) on, starting \(list(Array(words.prefix(shown))))."
    }

    /// True when the names are a subset of the five switches, in card order, with no repeats.
    public static func canonical(_ words: [String]) -> Bool {
        words == order.filter { words.contains($0) } && Set(words).count == words.count
    }

    private static func list(_ words: [String]) -> String {
        switch words.count {
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

public struct ReceiveSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var names: [String]

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, names: [String]) {
        self.draw = draw
        self.schedule = schedule
        self.names = names
    }

    /// A bad list draws Can't. None are on draws None. Otherwise Receive, then up to four switches that are on.
    public static func plan(words: [String]) -> ReceiveSetupDraw {
        guard ReceiveSetupAsk.canonical(words) else { return make(lines: ["Can't"], names: []) }
        if words.isEmpty { return make(lines: ["None"], names: []) }
        let shown = Array(words.prefix(ReceiveSetupAsk.shown))
        return make(lines: shown, names: shown)
    }

    /// The short line beside the bolt. The first beat says Receive.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Receive" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Receive"
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

    private static func make(lines: [String], names: [String]) -> ReceiveSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Receive"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ReceiveSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), names: names)
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
