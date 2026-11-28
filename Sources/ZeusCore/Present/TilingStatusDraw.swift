import Foundation

/// A spoken tiling status, and the cards drawn while Zeus answers it.
///
/// The voice says the same word the Tiling page shows. Turning tiling on stays a switch.
/// Dark Mode stays on its own card.
public enum TilingStatusAsk {
    public enum State: Equatable, Sendable {
        case off, on, paused, access, clash, keys
    }

    /// True for a direct ask about tiling. Turning it on is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["tiling"], ["tiling", "status"], ["is", "tiling", "on"], ["is", "tiling", "off"],
             ["is", "tiling", "paused"], ["what", "is", "tiling"], ["how", "is", "tiling"]:
            return true
        default:
            return false
        }
    }

    public static func card(_ state: State) -> String {
        switch state {
        case .off: "Off"
        case .on: "On"
        case .paused: "Paused"
        case .access: "Needs Accessibility"
        case .clash: "Key clash"
        case .keys: "Keys unavailable"
        }
    }

    public static func line(_ state: State) -> String {
        switch state {
        case .off: "Tiling is off."
        case .on: "Tiling is on."
        case .paused: "Tiling is paused."
        case .access: "Tiling needs Accessibility."
        case .clash: "Tiling has a key clash."
        case .keys: "Tiling keys are unavailable."
        }
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

public struct TilingStatusDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var state: TilingStatusAsk.State

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, state: TilingStatusAsk.State) {
        self.draw = draw
        self.schedule = schedule
        self.state = state
    }

    /// Tiling, then the same word the page shows.
    public static func plan(_ state: TilingStatusAsk.State) -> TilingStatusDraw {
        make(state: state, word: TilingStatusAsk.card(state))
    }

    /// The short line beside the bolt. The first beat says Tiling.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Tiling" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Tiling"
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

    private static func make(state: TilingStatusAsk.State, word: String) -> TilingStatusDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Tiling"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: word), at: 1),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TilingStatusDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), state: state)
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
