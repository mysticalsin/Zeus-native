import Foundation

/// A spoken check of the lid-closed rule and the frozen apps, and the cards drawn while Zeus answers it.
///
/// Whether the admin rule is ready, and how many apps freeze. App names stay off the card.
/// Lid-closed mode, mute, and the hotspot stay their own asks. The rule is not installed.
public enum FreezeSetupAsk {
    public static let unread = "I can't read the lid-closed rule."
    public static let rules = ["Ready", "Not set up", "Needs repair"]

    /// True for a direct ask about the rule or the frozen apps. The hotspot and the nudge are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "admin", "rule", "set"], ["is", "the", "insomnia", "rule", "set", "up"],
             ["how", "many", "apps", "freeze"], ["insomnia", "freeze", "settings"],
             ["how", "many", "apps", "freeze", "when", "the", "lid", "closes"],
             ["is", "lid", "closed", "mode", "ready"]:
            return true
        default:
            return false
        }
    }

    /// A known rule and a count from 0 to 999 use that sentence. Anything else is unread.
    public static func line(rule: String, frozen: String) -> String {
        guard known(rule: rule, frozen: frozen), let count = Int(frozen) else { return unread }
        return "The admin rule \(ruleWord(rule)), and \(frozenWord(count))."
    }

    public static func known(rule: String, frozen: String) -> Bool {
        rules.contains(rule) && knownCount(frozen)
    }

    private static func knownCount(_ value: String) -> Bool {
        guard let number = Int(value), (0...999).contains(number), String(number) == value else { return false }
        return true
    }

    private static func ruleWord(_ rule: String) -> String {
        switch rule {
        case "Ready": "is ready"
        case "Needs repair": "needs repair"
        default: "is not set up"
        }
    }

    private static func frozenWord(_ count: Int) -> String {
        switch count {
        case 0: "no apps freeze when the lid closes"
        case 1: "1 app freezes when the lid closes"
        default: "\(count) apps freeze when the lid closes"
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

public struct FreezeSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Rule, then the rule and the frozen count.
    public static func plan(rule: String, frozen: String) -> FreezeSetupDraw {
        guard FreezeSetupAsk.known(rule: rule, frozen: frozen) else { return make(lines: ["Can't"]) }
        return make(lines: ["Rule: \(rule)", "Frozen: \(frozen)"])
    }

    /// The short line beside the bolt. The first beat says Rule.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Rule" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Rule"
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

    private static func make(lines: [String]) -> FreezeSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Rule"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return FreezeSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
