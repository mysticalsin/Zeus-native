import Foundation

/// A keep-awake session Zeus starts or ends, drawn while it says so.
///
/// The voice says the full line. The screen builds Awake, then the length, On, Off, or Done.
/// A focus round stays on its own card.
public enum KeepAwakeAsk {
    public static let longestMinutes = 24 * 60
    public static let openEnded = "Awake until you stop it."
    public static let stopped = "Awake stopped."
    public static let done = "Awake time is up."
    public static let notOn = "Awake isn't on."

    public enum Command: Equatable, Sendable {
        /// Use the length already chosen for the Home cup.
        case startSaved
        /// Nil keeps the Mac awake until it is stopped.
        case start(Int?)
        case stop
    }

    /// A direct keep-awake command. A focus or weather ask is not this.
    public static func command(in text: String) -> Command? {
        let words = words(in: text)
        if let minutes = namedLength(words) { return .start(minutes) }
        switch words {
        case ["keep", "awake", "indefinitely"], ["stay", "awake", "indefinitely"],
             ["keep", "awake", "until", "i", "stop"]:
            return .start(nil)
        case ["keep", "awake"], ["stay", "awake"], ["keep", "the", "mac", "awake"], ["keep", "me", "awake"]:
            return .startSaved
        case ["stop", "keep", "awake"], ["end", "keep", "awake"], ["stop", "staying", "awake"],
             ["let", "the", "mac", "sleep"]:
            return .stop
        default:
            return nil
        }
    }

    public static func lengthLine(minutes: Int) -> String {
        "Awake for \(TimerDraw.duration(max(minutes, 0) * 60))."
    }

    private static func namedLength(_ words: [String]) -> Int? {
        let body: ArraySlice<String>
        if words.count >= 4, words.starts(with: ["keep", "awake", "for"]) || words.starts(with: ["stay", "awake", "for"]) {
            body = words.dropFirst(3)
        } else if words.count >= 6, words.starts(with: ["keep", "the", "mac", "awake", "for"]) {
            body = words.dropFirst(5)
        } else {
            return nil
        }
        return minutes(Array(body))
    }

    private static func minutes(_ words: [String]) -> Int? {
        guard words.count == 2, let count = Int(words[0]), count > 0 else { return nil }
        let total: Int
        switch words[1] {
        case "minute", "minutes", "min", "mins": total = count
        case "hour", "hours": total = count * 60
        default: return nil
        }
        guard total <= longestMinutes else { return nil }
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

public struct KeepAwakeDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.detail = detail
    }

    /// Nil when the length is under a minute.
    public static func plan(minutes: Int) -> KeepAwakeDraw? {
        guard minutes >= 1 else { return nil }
        return make(detail: TimerDraw.duration(minutes * 60))
    }

    public static func openEnded() -> KeepAwakeDraw { make(detail: "On") }
    public static func stopped() -> KeepAwakeDraw { make(detail: "Off") }
    public static func done() -> KeepAwakeDraw { make(detail: "Done") }

    /// The short line beside the bolt. The first beat says Awake.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Awake" }
        return Self.shortLine(detail)
    }

    /// Where the bolt sits: the ring first, then the detail card.
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

    private static func make(detail: String) -> KeepAwakeDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Awake"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: detail), at: 1),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return KeepAwakeDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), detail: detail)
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
