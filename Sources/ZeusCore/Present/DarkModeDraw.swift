import Foundation

/// A spoken Dark Mode reading, and the cards drawn while Zeus answers it.
///
/// The voice says whether the Mac is using Dark Mode. Brightness stays on its own card.
/// A recording stays on its own card.
public enum DarkModeAsk {
    public static let unread = "I can't read Dark Mode."

    /// True for a direct ask about Dark Mode. A brightness ask is not this.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["dark", "mode"], ["light", "mode"], ["is", "dark", "mode", "on"], ["is", "dark", "mode", "off"],
             ["is", "it", "dark", "mode"], ["is", "light", "mode", "on"],
             ["is", "the", "mac", "in", "dark", "mode"], ["is", "my", "mac", "in", "dark", "mode"],
             ["what", "is", "dark", "mode"], ["is", "appearance", "dark"]:
            return true
        default:
            return false
        }
    }

    public static func line(dark: Bool) -> String {
        dark ? "Dark Mode is on." : "Dark Mode is off."
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
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

public struct DarkModeDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var dark: Bool

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, dark: Bool) {
        self.draw = draw
        self.schedule = schedule
        self.dark = dark
    }

    /// Mode, then Dark or Light.
    public static func plan(dark: Bool) -> DarkModeDraw {
        make(state: dark ? "Dark" : "Light", dark: dark)
    }

    public static func unread() -> DarkModeDraw { make(state: "Can't", dark: false) }

    /// The short line beside the bolt. The first beat says Mode.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Mode" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Mode"
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

    private static func make(state: String, dark: Bool) -> DarkModeDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Mode"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: state), at: 1),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return DarkModeDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), dark: dark)
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
