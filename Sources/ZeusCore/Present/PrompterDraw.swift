import Foundation

/// A spoken teleprompter check, and the cards drawn while Zeus answers it.
///
/// The voice says the word count and the cue count, or the same status word the rolling page shows.
/// The script text stays off the card. Usage stays on its own card.
public enum PrompterAsk {
    public static let unread = "I can't read the script."
    public static let none = "No script yet."
    public static let liveWords = ["Rolling", "Paused", "Holding", "Waiting for you", "Get ready", "The end"]

    /// True for a direct ask about the prompter. A dictation word count is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "prompter"], ["how", "is", "my", "script"],
             ["how", "is", "the", "teleprompter"], ["how", "is", "my", "teleprompter"],
             ["is", "the", "prompter", "rolling"], ["is", "the", "teleprompter", "rolling"],
             ["is", "my", "script", "rolling"],
             ["how", "many", "words", "in", "my", "script"], ["how", "many", "words", "in", "the", "script"],
             ["how", "many", "cues"], ["how", "many", "cues", "in", "my", "script"],
             ["teleprompter"], ["prompter"], ["my", "script"]:
            return true
        default:
            return false
        }
    }

    /// True when the ask wants the counts even while the prompter is rolling.
    public static func wantsCounts(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "many", "words", "in", "my", "script"], ["how", "many", "words", "in", "the", "script"],
             ["how", "many", "cues"], ["how", "many", "cues", "in", "my", "script"]:
            return true
        default:
            return false
        }
    }

    /// Unread when the script cannot be seen. A live status uses the page's word. An empty script is None.
    public static func line(seen: Bool, words: Int, cues: Int, live: String?) -> String {
        guard seen else { return unread }
        if let live, liveWords.contains(live) { return liveLine(live) }
        if words < 1, cues < 1 { return none }
        return countLine(words: max(words, 0), cues: max(cues, 0))
    }

    private static func liveLine(_ live: String) -> String {
        switch live {
        case "Rolling": "The prompter is rolling."
        case "Paused": "The prompter is paused."
        case "Holding": "The prompter is holding."
        case "Waiting for you": "The prompter is waiting for you."
        case "Get ready": "Get ready."
        case "The end": "The prompter is at the end."
        default: unread
        }
    }

    private static func countLine(words: Int, cues: Int) -> String {
        let wordPart = words == 1 ? "1 word" : "\(words) words"
        let cuePart = cues == 1 ? "1 cue" : "\(cues) cues"
        if words < 1 { return "Your script has \(cuePart)." }
        if cues < 1 { return "Your script has \(wordPart)." }
        return "Your script has \(wordPart) and \(cuePart)."
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

public struct PrompterDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// Unseen draws Can't. A known live word draws that word. An empty script draws None. Otherwise the two counts.
    public static func plan(seen: Bool, words: Int, cues: Int, live: String?) -> PrompterDraw {
        guard seen else { return make(lines: ["Can't"], name: "") }
        if let live, PrompterAsk.liveWords.contains(live) { return make(lines: [live], name: live) }
        if words < 1, cues < 1 { return make(lines: ["None"], name: "") }
        return make(lines: ["\(max(words, 0))", "\(max(cues, 0))"], name: "")
    }

    /// The short line beside the bolt. The first beat says Script.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Script" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Script"
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

    private static func make(lines: [String], name: String) -> PrompterDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Script"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PrompterDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
