import Foundation

/// A spoken check of the cloud voice keys, and the cards drawn while Zeus answers it.
///
/// ElevenLabs, OpenAI, and Gemini: saved or not. The keys stay off the card.
/// Which voice speaks stays its own ask. Nothing is saved or removed.
public enum VoiceKeyAsk {
    public static let unread = "I can't read the voice keys."
    public static let marks = ["Saved", "None"]

    /// True for a direct ask about the voice keys. The chosen voice and Jev are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "voice", "keys", "are", "saved"], ["is", "the", "elevenlabs", "key", "saved"],
             ["is", "the", "openai", "voice", "key", "saved"], ["is", "the", "gemini", "voice", "key", "saved"],
             ["voice", "key", "settings"], ["how", "are", "the", "voice", "keys", "set"]:
            return true
        default:
            return false
        }
    }

    /// Three known choices use that sentence. Anything else is unread.
    public static func line(eleven: String, openAI: String, gemini: String) -> String {
        guard known(eleven: eleven, openAI: openAI, gemini: gemini) else { return unread }
        return "\(side("ElevenLabs", eleven)), \(side("OpenAI", openAI)), and \(side("Gemini", gemini))."
    }

    public static func known(eleven: String, openAI: String, gemini: String) -> Bool {
        marks.contains(eleven) && marks.contains(openAI) && marks.contains(gemini)
    }

    private static func side(_ name: String, _ mark: String) -> String {
        mark == "Saved" ? "\(name) has a saved key" : "\(name) has no key"
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

public struct VoiceKeyDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Keys, then ElevenLabs, OpenAI, and Gemini.
    public static func plan(eleven: String, openAI: String, gemini: String) -> VoiceKeyDraw {
        guard VoiceKeyAsk.known(eleven: eleven, openAI: openAI, gemini: gemini) else { return make(lines: ["Can't"]) }
        return make(lines: ["Eleven: \(eleven)", "OpenAI: \(openAI)", "Gemini: \(gemini)"])
    }

    /// The short line beside the bolt. The first beat says Keys.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Keys" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Keys"
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

    private static func make(lines: [String]) -> VoiceKeyDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Keys"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return VoiceKeyDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
