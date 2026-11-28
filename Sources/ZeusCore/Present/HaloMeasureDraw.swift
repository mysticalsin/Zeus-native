import Foundation

/// A spoken check of the halo's strength, speed, and thickness, and the cards drawn while Zeus answers it.
///
/// Each number is the value its slider shows. The entrance animation and the edge wave stay their own asks.
/// Nothing is played or changed.
public enum HaloMeasureAsk {
    public static let unread = "I can't read the halo measures."

    /// True for a direct ask about the three sliders. The entrance animation is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "strong", "is", "the", "entrance"], ["how", "fast", "is", "the", "entrance"],
             ["how", "thick", "is", "the", "halo"], ["entrance", "strength", "settings"],
             ["what", "is", "the", "entrance", "intensity"], ["how", "is", "the", "halo", "measured"]:
            return true
        default:
            return false
        }
    }

    /// Three numbers inside the slider ranges use that sentence. Anything else is unread.
    public static func line(strength: String, speed: String, thick: String) -> String {
        guard known(strength: strength, speed: speed, thick: thick),
              let strong = Int(strength), let fast = Int(speed), let wide = Int(thick) else { return unread }
        return "The entrance strength is \(strong), the speed is \(fast), and the light is \(wide) thick."
    }

    public static func known(strength: String, speed: String, thick: String) -> Bool {
        inRange(strength, 50...150) && inRange(speed, 50...200) && inRange(thick, 100...200)
    }

    private static func inRange(_ value: String, _ bounds: ClosedRange<Int>) -> Bool {
        guard let number = Int(value), bounds.contains(number), String(number) == value else { return false }
        return true
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

public struct HaloMeasureDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// A number outside a slider draws Can't. Otherwise Measure, then strength, speed, and thickness.
    public static func plan(strength: String, speed: String, thick: String) -> HaloMeasureDraw {
        guard HaloMeasureAsk.known(strength: strength, speed: speed, thick: thick) else { return make(lines: ["Can't"]) }
        return make(lines: ["Strength: \(strength)", "Speed: \(speed)", "Thick: \(thick)"])
    }

    /// The short line beside the bolt. The first beat says Measure.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Measure" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Measure"
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

    private static func make(lines: [String]) -> HaloMeasureDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Measure"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return HaloMeasureDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
