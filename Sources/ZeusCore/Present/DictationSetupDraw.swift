import Foundation

/// A spoken check of how dictation is set, and the cards drawn while Zeus answers it.
///
/// The titles match the language menu, the shortcut behavior, and the engine menu.
/// Whether dictation is on stays its own ask.
public enum DictationSetupAsk {
    public static let unread = "I can't read how dictation is set."
    public static let languages = ["Automatic", "English (US)", "English (UK)", "Portuguese (Brazil)", "French", "Spanish", "German", "Persian"]
    public static let keys = ["Hold to speak", "Press to start and stop"]
    public static let engines = ["Parakeet v3", "Parakeet Ultra", "Whisper turbo (WhisperKit)", "Whisper (whisper.cpp)", "Apple SpeechAnalyzer", "Apple on-device", "faster-whisper", "ElevenLabs Scribe v2", "OpenAI gpt-transcribe"]

    /// True for a direct ask about the dictation setup. The live phase is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "dictation", "set"], ["which", "dictation", "language"],
             ["what", "is", "the", "dictation", "language"], ["how", "do", "you", "dictate"],
             ["dictation", "language"], ["which", "language", "do", "you", "dictate"]:
            return true
        default:
            return false
        }
    }

    /// Three known titles use that sentence. Anything else is unread.
    public static func line(language: String, key: String, engine: String) -> String {
        guard known(language: language, key: key, engine: engine) else { return unread }
        return "Dictation uses \(language), \(key), and \(engine)."
    }

    public static func known(language: String, key: String, engine: String) -> Bool {
        languages.contains(language) && keys.contains(key) && engines.contains(engine)
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

public struct DictationSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown titles draw Can't. Otherwise Dictation, then the language, the key, and the engine.
    public static func plan(language: String, key: String, engine: String) -> DictationSetupDraw {
        guard DictationSetupAsk.known(language: language, key: key, engine: engine) else { return make(lines: ["Can't"]) }
        return make(lines: ["Language: \(language)", "Key: \(key)", "Engine: \(engine)"])
    }

    /// The short line beside the bolt. The first beat says Dictation.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Dictation" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Dictation"
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

    private static func make(lines: [String]) -> DictationSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Dictation"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return DictationSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
