import Foundation

/// A spoken check of how visual explanation hears, and the cards drawn while Zeus answers it.
///
/// The narration voice, the explanation microphone, caption mode, and whether a loaded Whisper model is used.
/// Voice names and device names stay off the card. The shortcut and local-only stay their own ask.
/// Nothing is spoken aloud, and the microphone is not opened.
public enum ExplainHearAsk {
    public static let unread = "I can't read how explanation hears."
    public static let places = ["System default", "Chosen", "Unavailable"]
    public static let switches = ["On", "Off"]

    /// True for a direct ask about narration or the explanation microphone. The shortcut is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "narration", "set"], ["which", "narration", "voice"],
             ["which", "explanation", "microphone"], ["is", "caption", "mode", "on"],
             ["narration", "settings"], ["is", "whisper", "used", "for", "explanation"]:
            return true
        default:
            return false
        }
    }

    /// Four known choices use that sentence. Anything else is unread.
    public static func line(voice: String, mic: String, caption: String, whisper: String) -> String {
        guard known(voice: voice, mic: mic, caption: caption, whisper: whisper) else { return unread }
        return "\(voiceLine(voice)), \(micLine(mic)), \(captionLine(caption)), and \(whisperLine(whisper))."
    }

    public static func known(voice: String, mic: String, caption: String, whisper: String) -> Bool {
        places.contains(voice) && places.contains(mic) && switches.contains(caption) && switches.contains(whisper)
    }

    private static func voiceLine(_ voice: String) -> String {
        switch voice {
        case "Chosen": "Narration uses a voice you chose"
        case "Unavailable": "The narration voice you chose is unavailable"
        default: "Narration uses the system default voice"
        }
    }

    private static func micLine(_ mic: String) -> String {
        switch mic {
        case "Chosen": "the explanation microphone is one you chose"
        case "Unavailable": "the explanation microphone you chose is unavailable"
        default: "the explanation microphone is the system default"
        }
    }

    private static func captionLine(_ caption: String) -> String {
        caption == "On" ? "caption mode is on" : "caption mode is off"
    }

    private static func whisperLine(_ whisper: String) -> String {
        whisper == "On" ? "Whisper is on" : "Whisper stays off"
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

public struct ExplainHearDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Narrate, then the voice, microphone, caption mode, and Whisper.
    public static func plan(voice: String, mic: String, caption: String, whisper: String) -> ExplainHearDraw {
        guard ExplainHearAsk.known(voice: voice, mic: mic, caption: caption, whisper: whisper) else { return make(lines: ["Can't"]) }
        return make(lines: ["Voice: \(voice)", "Mic: \(mic)", "Caption: \(caption)", "Whisper: \(whisper)"])
    }

    /// The short line beside the bolt. The first beat says Narrate.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Narrate" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Narrate"
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

    private static func make(lines: [String]) -> ExplainHearDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Narrate"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ExplainHearDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
