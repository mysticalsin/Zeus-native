import Foundation

/// A spoken check of when Zeus appears beside the pointer, and the cards drawn while Zeus answers it.
///
/// The titles match `BuddyShow.title`. The card style stays its own ask.
public enum PointerBuddyAsk {
    public static let unread = "I can't read when Zeus appears."
    /// The same titles as Show Zeus beside the pointer.
    public static let words = ["Always", "When I call him", "Never"]

    /// True for a direct ask about the pointer buddy. Pointing keys are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["when", "do", "you", "show", "up"], ["when", "are", "you", "beside", "the", "pointer"],
             ["when", "is", "zeus", "beside", "the", "pointer"], ["how", "is", "the", "pointer", "buddy"],
             ["when", "does", "zeus", "appear"], ["when", "do", "you", "appear"]:
            return true
        default:
            return false
        }
    }

    /// A known menu title uses that sentence. Anything else is unread.
    public static func line(word: String) -> String {
        switch word {
        case "Always": return "Zeus stays beside the pointer."
        case "When I call him": return "Zeus appears when you call him."
        case "Never": return "Zeus stays off the pointer."
        default: return unread
        }
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "when's", with: "when is")
        folded = folded.replacingOccurrences(of: "whens", with: "when is")
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

public struct PointerBuddyDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// An unknown word draws Can't. Otherwise Pointer, then the menu title.
    public static func plan(word: String) -> PointerBuddyDraw {
        guard PointerBuddyAsk.words.contains(word) else { return make(lines: ["Can't"], name: "") }
        return make(lines: [word], name: word)
    }

    /// The short line beside the bolt. The first beat says Pointer.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Pointer" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Pointer"
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

    private static func make(lines: [String], name: String) -> PointerBuddyDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Pointer"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PointerBuddyDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
