import Foundation

/// The time still left on a timer, drawn while Zeus says it.
///
/// The voice says the full line. The screen builds Left, then the length, then Running, Paused, Focus, or Break.
/// Setting a timer, and no timer at all, stay on their own cards.
public enum TimerLeftAsk {
    /// True for a direct ask about the time still left. A countdown and a new timer are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "much", "time", "is", "left"], ["how", "much", "time", "left"],
             ["how", "much", "time", "is", "remaining"], ["time", "left"], ["time", "remaining"],
             ["how", "long", "is", "left"], ["how", "long", "left"],
             ["how", "is", "my", "timer"], ["how", "my", "timer"],
             ["what", "is", "left", "on", "the", "timer"], ["what", "is", "left", "on", "my", "timer"]:
            return true
        default:
            return false
        }
    }

    /// "5 minutes left." Nil when the length is negative or the state is blank.
    public static func line(seconds: Int, state: String) -> String? {
        guard seconds >= 0, let state = shown(state) else { return nil }
        let length = TimerDraw.duration(seconds)
        switch state {
        case "Paused": return "\(length) left, paused."
        case "Break": return "\(length) left on the break."
        case "Focus": return "\(length) left on focus."
        default: return "\(length) left."
        }
    }

    static func shown(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(TalkDraw.maxTextCharacters))
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

public struct TimerLeftDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var length: String
    public var state: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, length: String, state: String) {
        self.draw = draw
        self.schedule = schedule
        self.length = length
        self.state = state
    }

    /// Nil when the length is negative or the state is blank.
    public static func plan(seconds: Int, state: String) -> TimerLeftDraw? {
        guard seconds >= 0, let state = TimerLeftAsk.shown(state) else { return nil }
        let length = TimerDraw.duration(seconds)
        return make(length: length, state: state)
    }

    /// The short line beside the bolt. The first beat says Left.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Left" }
        if last >= 2 { return state }
        return Self.shortLine(length)
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

    private static func make(length: String, state: String) -> TimerLeftDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Left"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: length), at: 1),
            .init(shape: .card(origin: .init(x: 920, y: 250), text: state), at: 2),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TimerLeftDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), length: length, state: state)
    }

    private static func shortLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > 40 { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? String(raw.prefix(40)) : line
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
