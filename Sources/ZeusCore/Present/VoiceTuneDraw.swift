import Foundation

/// A spoken check of how the voice is tuned, and the cards drawn while Zeus answers it.
///
/// ElevenLabs quality, the Ultron effect strength, and Kokoro pace.
/// Which voice speaks, and whether the effect is on, stay their own asks. Nothing is played.
public enum VoiceTuneAsk {
    public static let unread = "I can't read how the voice is tuned."
    public static let qualities = ["Fastest", "Studio"]

    /// True for a direct ask about the tuning. The chosen voice is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "voice", "tuned"], ["what", "is", "the", "voice", "quality"],
             ["how", "strong", "is", "the", "ultron", "effect"], ["what", "is", "the", "kokoro", "pace"],
             ["voice", "tune", "settings"], ["how", "fast", "is", "kokoro"]:
            return true
        default:
            return false
        }
    }

    /// A known quality, a percent from 0 to 100, and a pace from 0.70 to 1.30 use that sentence.
    public static func line(quality: String, effect: String, pace: String) -> String {
        guard known(quality: quality, effect: effect, pace: pace), let percent = Int(effect) else { return unread }
        return "Voice quality is \(quality), the effect is \(percent) percent, and Kokoro pace is \(pace) times."
    }

    public static func known(quality: String, effect: String, pace: String) -> Bool {
        qualities.contains(quality) && knownPercent(effect) && knownPace(pace)
    }

    private static func knownPercent(_ effect: String) -> Bool {
        guard let number = Int(effect), (0...100).contains(number), String(number) == effect else { return false }
        return true
    }

    private static func knownPace(_ pace: String) -> Bool {
        guard let value = Double(pace), (0.70...1.30).contains(value) else { return false }
        return pace == String(format: "%.2f", value)
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

public struct VoiceTuneDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Tune, then quality, effect, and pace.
    public static func plan(quality: String, effect: String, pace: String) -> VoiceTuneDraw {
        guard VoiceTuneAsk.known(quality: quality, effect: effect, pace: pace) else { return make(lines: ["Can't"]) }
        return make(lines: ["Quality: \(quality)", "Effect: \(effect)%", "Pace: \(pace)"])
    }

    /// The short line beside the bolt. The first beat says Tune.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Tune" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Tune"
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

    private static func make(lines: [String]) -> VoiceTuneDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Tune"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return VoiceTuneDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
