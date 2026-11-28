import Foundation

/// A spoken check of how dictation hears, and the cards drawn while Zeus answers it.
///
/// The microphone is the system default, one you chose, or a chosen one that is gone, plus the cue volume.
/// A device name stays off the card. The talk microphone and the cue style stay their own asks.
/// Listening does not start and the cue is not played.
public enum DictateHearAsk {
    public static let unread = "I can't read the dictation microphone."
    public static let inputs = ["System default", "Chosen", "Unavailable"]

    /// True for a direct ask about dictation's microphone or cue volume. Talk's microphone is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "dictation", "microphone"], ["what", "is", "the", "dictation", "microphone"],
             ["how", "is", "the", "dictation", "mic", "set"], ["dictation", "microphone", "settings"],
             ["how", "loud", "is", "the", "dictation", "cue"], ["what", "is", "the", "dictation", "cue", "volume"]:
            return true
        default:
            return false
        }
    }

    /// A known input and a percent from 0 to 100 use that sentence. Anything else is unread.
    public static func line(input: String, cue: String) -> String {
        guard known(input: input, cue: cue), let percent = Int(cue) else { return unread }
        return "\(heard(input)), and the cue is \(percent) percent."
    }

    public static func known(input: String, cue: String) -> Bool {
        inputs.contains(input) && knownCue(cue)
    }

    private static func knownCue(_ cue: String) -> Bool {
        guard let number = Int(cue), (0...100).contains(number), String(number) == cue else { return false }
        return true
    }

    private static func heard(_ input: String) -> String {
        switch input {
        case "System default": "Dictation uses the system default microphone"
        case "Chosen": "Dictation uses a microphone you chose"
        default: "The dictation microphone you chose is unavailable"
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

public struct DictateHearDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Input, then the microphone and the cue.
    public static func plan(input: String, cue: String) -> DictateHearDraw {
        guard DictateHearAsk.known(input: input, cue: cue) else { return make(lines: ["Can't"]) }
        return make(lines: ["Input: \(input)", "Cue: \(cue)%"])
    }

    /// The short line beside the bolt. The first beat says Input.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Input" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Input"
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

    private static func make(lines: [String]) -> DictateHearDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Input"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return DictateHearDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
