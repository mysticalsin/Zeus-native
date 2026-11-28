import Foundation

/// A spoken check of the named cloud voices, and the cards drawn while Zeus answers it.
///
/// The OpenAI voice and the Gemini voice, or none when that key is not saved.
/// Kokoro, which engine speaks, and whether a key is saved stay their own asks. Nothing is played or saved.
public enum CloudVoiceAsk {
    public static let unread = "I can't read the cloud voices."
    public static let openAI = [
        "None", "Ended",
        "Alloy", "Ash", "Ballad", "Cedar", "Coral", "Echo", "Fable", "Marin", "Nova", "Onyx", "Sage", "Shimmer", "Verse",
    ]
    public static let gemini = [
        "None",
        "Achernar", "Achird", "Algenib", "Algieba", "Alnilam", "Aoede", "Autonoe", "Callirrhoe", "Charon",
        "Despina", "Enceladus", "Erinome", "Fenrir", "Gacrux", "Iapetus", "Kore", "Laomedeia", "Leda",
        "Orus", "Puck", "Pulcherrima", "Rasalgethi", "Sadachbia", "Sadaltager", "Schedar", "Sulafat",
        "Umbriel", "Vindemiatrix", "Zephyr", "Zubenelgenubi",
    ]

    /// True for a direct ask about the named cloud voices. Kokoro and the keys are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "openai", "voice"], ["which", "gemini", "voice"],
             ["which", "cloud", "voices"], ["cloud", "voice", "settings"],
             ["how", "are", "the", "cloud", "voices", "set"], ["what", "are", "the", "named", "voices"]:
            return true
        default:
            return false
        }
    }

    /// Two known names use that sentence. Anything else is unread.
    public static func line(openAI: String, gemini: String) -> String {
        guard known(openAI: openAI, gemini: gemini) else { return unread }
        return "OpenAI voice is \(spoken(openAI)), and Gemini voice is \(spoken(gemini))."
    }

    public static func known(openAI: String, gemini: String) -> Bool {
        self.openAI.contains(openAI) && self.gemini.contains(gemini)
    }

    private static func spoken(_ name: String) -> String {
        switch name {
        case "None": "none"
        case "Ended": "ended"
        default: name
        }
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
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

public struct CloudVoiceDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown name draws Can't. Otherwise Cast, then the two voices.
    public static func plan(openAI: String, gemini: String) -> CloudVoiceDraw {
        guard CloudVoiceAsk.known(openAI: openAI, gemini: gemini) else { return make(lines: ["Can't"]) }
        return make(lines: ["OpenAI: \(openAI)", "Gemini: \(gemini)"])
    }

    /// The short line beside the bolt. The first beat says Cast.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Cast" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Cast"
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

    private static func make(lines: [String]) -> CloudVoiceDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Cast"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return CloudVoiceDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
