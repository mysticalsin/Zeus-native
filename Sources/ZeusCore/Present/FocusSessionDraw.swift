import Foundation

/// A focus session Zeus starts, pauses, stops, or finishes, drawn while it says so.
///
/// The voice says the full line. The screen builds Focus or Break, then the length,
/// Paused, Stopped, or Done. A plain countdown stays on the timer card.
public enum FocusSessionAsk {
    public static let longestSeconds = 180 * 60
    public static let paused = "Focus paused."
    public static let focusStopped = "Focus stopped."
    public static let breakStopped = "Break stopped."
    public static let notRunning = "Focus isn't running."
    public static let focusDone = "Focus done. Take a break."
    public static let breakOver = "Break over. Back to it."

    public enum Command: Equatable, Sendable {
        /// Nil keeps the length already set on the clock.
        case start(Int?)
        case pause
        case resume
        case stop
    }

    /// A direct focus command. A timer command is not this.
    public static func command(in text: String) -> Command? {
        let words = words(in: text)
        if let seconds = namedLength(words) { return .start(seconds) }
        switch words {
        case ["start", "focus"], ["start", "a", "focus"], ["start", "the", "focus"],
             ["start", "focusing"], ["start", "a", "focus", "session"], ["begin", "focus"]:
            return .start(nil)
        case ["pause", "focus"], ["pause", "the", "focus"], ["pause", "focusing"]:
            return .pause
        case ["resume", "focus"], ["resume", "the", "focus"], ["resume", "focusing"], ["continue", "focus"]:
            return .resume
        case ["stop", "focus"], ["stop", "the", "focus"], ["end", "focus"], ["end", "the", "focus"], ["stop", "focusing"]:
            return .stop
        default:
            return nil
        }
    }

    public static func lengthLine(seconds: Int, breakTime: Bool) -> String {
        let length = TimerDraw.duration(max(seconds, 0))
        return breakTime ? "Break for \(length)." : "Focus for \(length)."
    }

    /// "focus for 25 minutes", "start focus for 25 minutes", "start a 25 minute focus".
    private static func namedLength(_ words: [String]) -> Int? {
        let body: ArraySlice<String>
        if words.count >= 3, words[0] == "focus", words[1] == "for" {
            body = words.dropFirst(2)
        } else if words.count >= 4, words[0] == "start", words[1] == "focus", words[2] == "for" {
            body = words.dropFirst(3)
        } else if words.count >= 5, words[0] == "start", words[1] == "a" || words[1] == "an", words.last == "focus" {
            body = words.dropFirst(2).dropLast()
        } else {
            return nil
        }
        return duration(Array(body))
    }

    private static func duration(_ words: [String]) -> Int? {
        guard words.count == 2, let count = Int(words[0]), count > 0 else { return nil }
        let unit: Int
        switch words[1] {
        case "second", "seconds": unit = 1
        case "minute", "minutes", "min", "mins": unit = 60
        case "hour", "hours": unit = 3600
        default: return nil
        }
        let total = count * unit
        guard total <= longestSeconds else { return nil }
        return total
    }

    private static func words(in text: String) -> [String] {
        let folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { token -> String in
            var word = String(token)
            if word.hasSuffix("'s"), word.count > 3 { word = String(word.dropLast(2)) }
            return word.replacingOccurrences(of: "'", with: "")
        }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "zeus", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct FocusSessionDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var lead: String
    public var cards: [String]

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, lead: String, cards: [String]) {
        self.draw = draw
        self.schedule = schedule
        self.lead = lead
        self.cards = cards
    }

    /// Nil when the length is negative.
    public static func plan(seconds: Int, breakTime: Bool) -> FocusSessionDraw? {
        guard seconds >= 0 else { return nil }
        let lead = breakTime ? "Break" : "Focus"
        return make(lead: lead, cards: [TimerDraw.duration(seconds)])
    }

    public static func paused() -> FocusSessionDraw {
        make(lead: "Focus", cards: ["Paused"])
    }

    public static func stopped(breakTime: Bool) -> FocusSessionDraw {
        make(lead: breakTime ? "Break" : "Focus", cards: ["Stopped"])
    }

    public static func ready() -> FocusSessionDraw {
        make(lead: "Focus", cards: ["Ready"])
    }

    public static func focusDone() -> FocusSessionDraw {
        make(lead: "Focus", cards: ["Done", "Break"])
    }

    public static func breakOver() -> FocusSessionDraw {
        make(lead: "Break", cards: ["Done"])
    }

    /// The short line beside the bolt. The first beat names Focus or Break.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return lead }
        let index = last - 1
        guard cards.indices.contains(index) else { return lead }
        return Self.shortLine(cards[index])
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

    private static func make(lead: String, cards: [String]) -> FocusSessionDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: lead), at: 0),
        ]
        for (index, text) in cards.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return FocusSessionDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), lead: lead, cards: cards)
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
