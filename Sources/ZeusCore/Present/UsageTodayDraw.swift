import Foundation

/// One provider the Usage tab can show.
public struct UsageTodayFact: Equatable, Sendable {
    public var name: String
    public var today: Int
    public var hasData: Bool

    public init(name: String, today: Int, hasData: Bool) {
        self.name = name
        self.today = today
        self.hasData = hasData
    }
}

/// A spoken usage total, and the cards drawn while Zeus answers it.
///
/// The voice says today's tokens for the busiest agent, in the same compact form the Usage tab shows.
/// The dollar cost and the model name stay off the card. Earbuds stay on their own card.
public enum UsageTodayAsk {
    public static let unread = "I can't read usage yet."
    public static let none = "No sessions this week."

    /// True for a direct ask about today's usage. A dictation word count is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "much", "did", "i", "use", "today"], ["how", "much", "have", "i", "used", "today"],
             ["how", "many", "tokens", "today"], ["how", "many", "tokens", "did", "i", "use"],
             ["what", "is", "my", "usage"], ["how", "is", "my", "usage"],
             ["usage", "today"], ["my", "usage"]:
            return true
        default:
            return false
        }
    }

    /// The name that fits on the card. Blank is nil.
    public static func cardName(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        return String(flat.prefix(TalkDraw.maxTextCharacters))
    }

    /// The same compact form as `UsageSummary.compact`. Negative is nil.
    public static func countWord(_ tokens: Int) -> String? {
        guard tokens >= 0 else { return nil }
        switch tokens {
        case 1_000_000_000...: return String(format: "%.1fB", Double(tokens) / 1_000_000_000)
        case 1_000_000...: return String(format: tokens >= 10_000_000 ? "%.0fM" : "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...: return String(format: tokens >= 100_000 ? "%.0fk" : "%.1fk", Double(tokens) / 1_000)
        default: return "\(tokens)"
        }
    }

    /// Empty is unread. No session this week stays on None. Otherwise the busiest agent.
    public static func line(facts: [UsageTodayFact]) -> String {
        guard !facts.isEmpty else { return unread }
        let shown = facts.filter(\.hasData)
        guard !shown.isEmpty else { return none }
        guard let lead = busiest(shown), let name = cardName(lead.name), let word = countWord(lead.today) else { return unread }
        let amount = word == "0" ? "\(name) used nothing today." : "\(name) used \(word) tokens today."
        guard shown.count > 1 else { return amount }
        return "\(shown.count) agents. \(amount)"
    }

    /// The provider with the most tokens today. A tie keeps the earlier one.
    static func busiest(_ facts: [UsageTodayFact]) -> UsageTodayFact? {
        facts.max { $0.today < $1.today }
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

public struct UsageTodayDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// Empty draws Can't. No sessions draw None. Otherwise the busiest name, then today's tokens.
    public static func plan(facts: [UsageTodayFact]) -> UsageTodayDraw {
        guard !facts.isEmpty else { return make(lines: ["Can't"], name: "") }
        let shown = facts.filter(\.hasData)
        guard !shown.isEmpty else { return make(lines: ["None"], name: "") }
        guard let lead = UsageTodayAsk.busiest(shown),
              let name = UsageTodayAsk.cardName(lead.name),
              let word = UsageTodayAsk.countWord(lead.today) else {
            return make(lines: ["Can't"], name: "")
        }
        if shown.count > 1 {
            return make(lines: ["\(shown.count)", name, word], name: name)
        }
        return make(lines: [name, word], name: name)
    }

    /// The short line beside the bolt. The first beat says Usage.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Usage" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Usage"
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

    private static func make(lines: [String], name: String) -> UsageTodayDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Usage"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return UsageTodayDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
