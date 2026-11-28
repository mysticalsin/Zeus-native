import Foundation

/// A spoken check of the four Home cards, and the cards drawn while Zeus answers it.
///
/// The titles match `HomeWidgetKind.title`. Today's brief stays its own ask.
public enum HomeCardsAsk {
    public static let unread = "I can't read the Home cards."
    /// The same titles as the Home slot menu.
    public static let words = ["Music", "Focus", "Weather", "Calendar", "Clock", "World clock", "Month", "Agenda", "Countdown", "Note", "Battery", "Agents"]

    /// True for a direct ask about the Home cards. The agenda and the shelf stay off.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["what", "is", "on", "home"], ["what", "is", "on", "the", "home"],
             ["which", "home", "cards"], ["what", "are", "the", "home", "cards"],
             ["home", "cards"], ["what", "is", "home", "showing"]:
            return true
        default:
            return false
        }
    }

    /// Four known titles use that sentence. Anything else is unread.
    public static func line(words: [String]) -> String {
        guard words.count == 4, words.allSatisfy({ Self.words.contains($0) }) else { return unread }
        return "Home shows \(words[0]), \(words[1]), \(words[2]), and \(words[3])."
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
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

public struct HomeCardsDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var names: [String]

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, names: [String]) {
        self.draw = draw
        self.schedule = schedule
        self.names = names
    }

    /// Four known titles draw Home, then each card. Anything else draws Can't.
    public static func plan(words: [String]) -> HomeCardsDraw {
        guard words.count == 4, words.allSatisfy({ HomeCardsAsk.words.contains($0) }) else {
            return make(lines: ["Can't"], names: [])
        }
        return make(lines: words, names: words)
    }

    /// The short line beside the bolt. The first beat says Home.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Home" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Home"
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

    private static func make(lines: [String], names: [String]) -> HomeCardsDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Home"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return HomeCardsDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), names: names)
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
