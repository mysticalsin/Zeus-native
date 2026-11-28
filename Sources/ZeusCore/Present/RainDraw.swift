import Foundation

/// A spoken rain ask, and the cards drawn while Zeus answers it.
///
/// The voice says when the rain arrives. The screen builds Rain, then the wait.
/// Rain that has started shows Now. The weather forecast stays on its own card.
public enum RainAsk {
    public static let now = "It's raining."
    public static let none = "No rain is coming."
    public static let notReady = "I don't have a rain forecast."

    /// True for a direct rain ask. The general forecast is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["will", "it", "rain"], ["is", "it", "going", "to", "rain"],
             ["when", "will", "it", "rain"], ["when", "is", "it", "going", "to", "rain"],
             ["when", "is", "the", "rain"], ["is", "rain", "coming"], ["any", "rain"],
             ["rain", "soon"], ["is", "it", "raining"], ["when", "does", "it", "rain"]:
            return true
        default:
            return false
        }
    }

    /// 1...360 minutes, or nil.
    public static func minutes(until date: Date, now: Date) -> Int? {
        let raw = Int(date.timeIntervalSince(now) / 60)
        guard (1...360).contains(raw) else { return nil }
        return raw
    }

    /// Nil when the wait is outside 1...360 minutes.
    public static func line(minutes: Int) -> String? {
        guard let words = length(minutes: minutes, card: false) else { return nil }
        return "Rain in \(words)."
    }

    /// "25 min" on the card, "25 minutes" in the sentence. Two hours and beyond use hours.
    public static func length(minutes: Int, card: Bool) -> String? {
        guard (1...360).contains(minutes) else { return nil }
        if minutes < 120 {
            if card { return "\(minutes) min" }
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let hours = Int((Double(minutes) / 60).rounded())
        if card { return hours == 1 ? "1 hr" : "\(hours) hr" }
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "when's", with: "when is")
        folded = folded.replacingOccurrences(of: "whens", with: "when is")
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

public struct RainDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.detail = detail
    }

    /// Nil when the wait is outside 1...360 minutes.
    public static func plan(minutes: Int) -> RainDraw? {
        guard let card = RainAsk.length(minutes: minutes, card: true),
              RainAsk.line(minutes: minutes) != nil else { return nil }
        return make(detail: card)
    }

    public static func now() -> RainDraw { make(detail: "Now") }
    public static func none() -> RainDraw { make(detail: "None") }
    public static func notReady() -> RainDraw { make(detail: "Wait") }

    /// The short line beside the bolt. The first beat says Rain.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Rain" }
        return detail
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

    private static func make(detail: String) -> RainDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Rain"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: detail), at: 1),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return RainDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), detail: detail)
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
