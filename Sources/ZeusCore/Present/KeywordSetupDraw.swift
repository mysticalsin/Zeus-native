import Foundation

/// A spoken check of approval keywords, and the cards drawn while Zeus answers it.
///
/// Whether Zeus listens, and whether approve, deny, and open still use the default words.
/// A waiting approval stays its own ask. Custom words stay off the card. Nothing is changed.
public enum KeywordSetupAsk {
    public static let unread = "I can't read the approval words."
    public static let switches = ["On", "Off"]
    public static let lists = ["Default", "Custom"]
    public static let approveDefault = "ok, yes, approve, allow"
    public static let denyDefault = "no, deny, stop"
    public static let openDefault = "open, show me"

    /// True for a direct ask about approval keywords. A live approval and dictation words are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "are", "approval", "words", "set"], ["are", "approval", "keywords", "on"],
             ["which", "approval", "words"], ["approval", "keyword", "settings"],
             ["how", "is", "keyword", "approval", "set"], ["does", "zeus", "listen", "for", "approval", "words"]:
            return true
        default:
            return false
        }
    }

    /// A stored list matches the catalog default, or it is custom. The words themselves are not returned.
    public static func wordState(_ stored: String, default fallback: String) -> String {
        stored == fallback ? "Default" : "Custom"
    }

    /// Four known choices use that sentence. Anything else is unread.
    public static func line(listen: String, approve: String, deny: String, open: String) -> String {
        guard known(listen: listen, approve: approve, deny: deny, open: open) else { return unread }
        return "Approval listening is \(word(listen)). \(clause("Approve", approve)), \(clause("deny", deny)), and \(clause("open", open))."
    }

    public static func known(listen: String, approve: String, deny: String, open: String) -> Bool {
        switches.contains(listen) && lists.contains(approve) && lists.contains(deny) && lists.contains(open)
    }

    private static func word(_ value: String) -> String { value == "On" ? "on" : "off" }

    private static func clause(_ name: String, _ state: String) -> String {
        state == "Default" ? "\(name) uses the default words" : "\(name) uses your own words"
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

public struct KeywordSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Keywords, then listening and the three lists.
    public static func plan(listen: String, approve: String, deny: String, open: String) -> KeywordSetupDraw {
        guard KeywordSetupAsk.known(listen: listen, approve: approve, deny: deny, open: open) else { return make(lines: ["Can't"]) }
        return make(lines: ["Listen: \(listen)", "Approve: \(approve)", "Deny: \(deny)", "Open: \(open)"])
    }

    /// The short line beside the bolt. The first beat says Keywords.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Keywords" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Keywords"
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

    private static func make(lines: [String]) -> KeywordSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Keywords"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return KeywordSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
