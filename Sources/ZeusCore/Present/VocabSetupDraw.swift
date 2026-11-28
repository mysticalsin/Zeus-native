import Foundation

/// A spoken check of the dictation vocabulary, and the cards drawn while Zeus answers it.
///
/// How many words to listen for, and how many replacements. The words stay off the card.
/// Today's dictated count and the microphone stay their own asks. Nothing is saved.
public enum VocabSetupAsk {
    public static let unread = "I can't read the dictation vocabulary."

    /// True for a direct ask about the vocabulary. Today's word count is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "vocabulary", "set"], ["how", "many", "vocabulary", "words"],
             ["how", "many", "dictation", "replacements"], ["dictation", "vocabulary", "settings"],
             ["are", "there", "vocabulary", "words"], ["how", "is", "dictation", "vocabulary", "set"]:
            return true
        default:
            return false
        }
    }

    /// Two counts from 0 to 999 use that sentence. Anything else is unread.
    public static func line(words: String, fixes: String) -> String {
        guard known(words: words, fixes: fixes), let wordCount = Int(words), let fixCount = Int(fixes) else { return unread }
        return "\(wordLine(wordCount)), and \(fixLine(fixCount))."
    }

    public static func known(words: String, fixes: String) -> Bool {
        knownCount(words) && knownCount(fixes)
    }

    private static func knownCount(_ value: String) -> Bool {
        guard let number = Int(value), (0...999).contains(number), String(number) == value else { return false }
        return true
    }

    private static func wordLine(_ count: Int) -> String {
        switch count {
        case 0: "No vocabulary words"
        case 1: "1 vocabulary word"
        default: "\(count) vocabulary words"
        }
    }

    private static func fixLine(_ count: Int) -> String {
        switch count {
        case 0: "no replacements"
        case 1: "1 replacement"
        default: "\(count) replacements"
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

public struct VocabSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// A count outside 0 to 999 draws Can't. Otherwise Terms, then the two counts.
    public static func plan(words: String, fixes: String) -> VocabSetupDraw {
        guard VocabSetupAsk.known(words: words, fixes: fixes) else { return make(lines: ["Can't"]) }
        return make(lines: ["Words: \(words)", "Fixes: \(fixes)"])
    }

    /// The short line beside the bolt. The first beat says Terms.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Terms" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Terms"
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

    private static func make(lines: [String]) -> VocabSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Terms"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return VocabSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
