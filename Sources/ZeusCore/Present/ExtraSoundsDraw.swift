import Foundation

/// A spoken check of the extra agent sounds, and the cards drawn while Zeus answers it.
///
/// Timer alarms, the failure sound, the start chime, and the loop while an agent works.
/// The cue styles, which events play, and the voice cues stay their own asks. Nothing is played.
public enum ExtraSoundsAsk {
    public static let unread = "I can't read the extra sounds."
    public static let switches = ["On", "Off"]

    /// True for a direct ask about the extra sounds. Cue styles and sound events are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "extra", "sounds"], ["how", "is", "the", "extra", "sounds", "set"],
             ["extra", "sound", "settings"], ["are", "timer", "alarms", "on"],
             ["is", "the", "failure", "sound", "on"], ["is", "the", "working", "loop", "on"]:
            return true
        default:
            return false
        }
    }

    /// Four known switches use that sentence. Anything else is unread.
    public static func line(timer: String, fail: String, start: String, loop: String) -> String {
        guard known(timer: timer, fail: fail, start: start, loop: loop) else { return unread }
        return "Timer alarms are \(word(timer)), the failure sound is \(word(fail)), the start chime is \(word(start)), and the working loop is \(word(loop))."
    }

    public static func known(timer: String, fail: String, start: String, loop: String) -> Bool {
        switches.contains(timer) && switches.contains(fail) && switches.contains(start) && switches.contains(loop)
    }

    private static func word(_ value: String) -> String { value == "On" ? "on" : "off" }

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

public struct ExtraSoundsDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown switches draw Can't. Otherwise Extra, then the four sounds.
    public static func plan(timer: String, fail: String, start: String, loop: String) -> ExtraSoundsDraw {
        guard ExtraSoundsAsk.known(timer: timer, fail: fail, start: start, loop: loop) else { return make(lines: ["Can't"]) }
        return make(lines: ["Timer: \(timer)", "Fail: \(fail)", "Start: \(start)", "Loop: \(loop)"])
    }

    /// The short line beside the bolt. The first beat says Extra.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Extra" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Extra"
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

    private static func make(lines: [String]) -> ExtraSoundsDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Extra"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ExtraSoundsDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
