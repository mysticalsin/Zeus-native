import Foundation

/// A spoken check of muted apps and trusted chats, and the cards drawn while Zeus answers it.
///
/// How many apps are muted, and how many chats are trusted. Names and projects stay off the card.
/// Waiting notifications stay their own ask. Nothing is unmuted or cleared.
public enum QuietSetupAsk {
    public static let unread = "I can't read muted apps or trusted chats."

    /// True for a direct ask about muted apps or trusted chats. The waiting count is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "many", "apps", "are", "muted"], ["are", "any", "apps", "muted"],
             ["how", "many", "chats", "are", "trusted"], ["are", "any", "chats", "trusted"],
             ["quiet", "app", "settings"], ["how", "is", "trust", "set"]:
            return true
        default:
            return false
        }
    }

    /// Two counts from 0 to 999 use that sentence. Anything else is unread.
    public static func line(muted: String, trusted: String) -> String {
        guard known(muted: muted, trusted: trusted), let apps = Int(muted), let chats = Int(trusted) else { return unread }
        return "\(appsLine(apps)), and \(chatsLine(chats))."
    }

    public static func known(muted: String, trusted: String) -> Bool {
        knownCount(muted) && knownCount(trusted)
    }

    private static func knownCount(_ value: String) -> Bool {
        guard let number = Int(value), (0...999).contains(number), String(number) == value else { return false }
        return true
    }

    private static func appsLine(_ count: Int) -> String {
        switch count {
        case 0: "No apps are muted"
        case 1: "1 app is muted"
        default: "\(count) apps are muted"
        }
    }

    private static func chatsLine(_ count: Int) -> String {
        switch count {
        case 0: "no chats are trusted"
        case 1: "1 chat is trusted"
        default: "\(count) chats are trusted"
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

public struct QuietSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// A count outside 0 to 999 draws Can't. Otherwise Quiet, then the two counts.
    public static func plan(muted: String, trusted: String) -> QuietSetupDraw {
        guard QuietSetupAsk.known(muted: muted, trusted: trusted) else { return make(lines: ["Can't"]) }
        return make(lines: ["Muted: \(muted)", "Trusted: \(trusted)"])
    }

    /// The short line beside the bolt. The first beat says Quiet.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Quiet" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Quiet"
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

    private static func make(lines: [String]) -> QuietSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Quiet"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return QuietSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
