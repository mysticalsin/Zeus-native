import Foundation

/// A spoken Caps Lock reading, and the cards drawn while Zeus answers it.
///
/// The voice says whether Caps Lock is on. The keyboard backlight stays on its own cue.
/// The front app stays on its own card.
public enum CapsLockAsk {
    /// True for a direct ask about Caps Lock. A brightness ask is not this.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["caps", "lock"], ["capslock"], ["is", "caps", "lock", "on"], ["is", "capslock", "on"],
             ["is", "my", "caps", "lock", "on"], ["is", "the", "caps", "lock", "on"],
             ["what", "is", "caps", "lock"], ["what", "is", "my", "caps", "lock"],
             ["what", "is", "capslock"], ["caps", "lock", "status"], ["is", "caps", "lock", "off"]:
            return true
        default:
            return false
        }
    }

    public static func line(on: Bool) -> String {
        on ? "Caps Lock is on." : "Caps Lock is off."
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

public struct CapsLockDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var on: Bool

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, on: Bool) {
        self.draw = draw
        self.schedule = schedule
        self.on = on
    }

    /// Caps, then On or Off.
    public static func plan(on: Bool) -> CapsLockDraw {
        make(state: on ? "On" : "Off", on: on)
    }

    /// The short line beside the bolt. The first beat says Caps.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Caps" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Caps"
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

    private static func make(state: String, on: Bool) -> CapsLockDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Caps"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: state), at: 1),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return CapsLockDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), on: on)
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
