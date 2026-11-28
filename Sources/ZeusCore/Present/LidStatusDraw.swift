import Foundation

/// A spoken lid-closed check, and the cards drawn while Zeus answers it.
///
/// The voice says the same lid line the Insomnia page shows.
/// A long arming failure stays off the spoken line. The prompter stays on its own card.
public enum LidStatusAsk {
    public static let unread = "I can't read the lid."

    /// True for a direct ask about the lid. Keep-awake is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "lid"], ["how", "is", "lid", "closed", "mode"],
             ["is", "the", "lid", "closed"], ["is", "the", "lid", "open"],
             ["is", "lid", "closed", "mode", "on"], ["lid", "closed", "mode"],
             ["lid"], ["insomnia"]:
            return true
        default:
            return false
        }
    }

    /// The page word that fits on the card. Blank is nil.
    public static func cardWord(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        return String(flat.prefix(TalkDraw.maxTextCharacters))
    }

    /// Blank is unread. A known page word uses that sentence. Any other not-armed line stays short.
    public static func line(word: String) -> String {
        guard let word = cardWord(word) else { return unread }
        switch word {
        case "Off": return "Lid-closed mode is off."
        case "Arming\u{2026}": return "Lid-closed mode is arming."
        case "Not armed: needs setup", "Needs setup": return "Lid-closed mode needs setup."
        case "Armed when you start": return "Lid-closed mode arms when you start."
        case "Closed, still working": return "The lid is closed, and the Mac is still working."
        case "Open": return "The lid is open."
        case "No lid on this Mac": return "This Mac has no lid."
        default:
            return word.hasPrefix("Not armed") ? "Lid-closed mode is not armed." : unread
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

public struct LidStatusDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// A blank or unknown page word draws Can't. Otherwise Lid, then that word.
    public static func plan(word: String) -> LidStatusDraw {
        guard let shown = LidStatusAsk.cardWord(word), LidStatusAsk.line(word: shown) != LidStatusAsk.unread else {
            return make(lines: ["Can't"], name: "")
        }
        return make(lines: [shown], name: shown)
    }

    /// The short line beside the bolt. The first beat says Lid.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Lid" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Lid"
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

    private static func make(lines: [String], name: String) -> LidStatusDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Lid"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return LidStatusDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
