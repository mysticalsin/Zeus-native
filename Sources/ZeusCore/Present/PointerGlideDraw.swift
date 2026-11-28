import Foundation

/// A spoken check of the system pointer, and the cards drawn while Zeus answers it.
///
/// The settings switch and the engine that actually glides. They can disagree.
/// When Zeus may drive stays its own ask. The pointer is not moved.
public enum PointerGlideAsk {
    public static let unread = "I can't read the system pointer."
    public static let switches = ["On", "Off"]

    /// True for a direct ask about the system pointer. Drive permission is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["does", "zeus", "move", "the", "system", "pointer"], ["is", "the", "system", "pointer", "on"],
             ["how", "is", "the", "system", "pointer", "set"], ["system", "pointer", "settings"],
             ["can", "drive", "glide", "the", "pointer"], ["is", "the", "pointer", "engine", "on"]:
            return true
        default:
            return false
        }
    }

    /// Two known switches use that sentence. Anything else is unread.
    public static func line(shown: String, engine: String) -> String {
        guard known(shown: shown, engine: engine) else { return unread }
        return "The pointer switch is \(word(shown)), and the pointer engine is \(word(engine))."
    }

    public static func known(shown: String, engine: String) -> Bool {
        switches.contains(shown) && switches.contains(engine)
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

public struct PointerGlideDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown switch draws Can't. Otherwise Glide, then the switch and the engine.
    public static func plan(shown: String, engine: String) -> PointerGlideDraw {
        guard PointerGlideAsk.known(shown: shown, engine: engine) else { return make(lines: ["Can't"]) }
        return make(lines: ["Switch: \(shown)", "Engine: \(engine)"])
    }

    /// The short line beside the bolt. The first beat says Glide.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Glide" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Glide"
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

    private static func make(lines: [String]) -> PointerGlideDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Glide"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PointerGlideDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
