import Foundation

/// A spoken check of how pointing draws, and the cards drawn while Zeus answers it.
///
/// Whether pointing is on, the trail while the keys are held, a screenshot with each question, and typed questions.
/// The pointing keys stay their own ask. Nothing is started, drawn, or sent.
public enum PointTrailAsk {
    public static let unread = "I can't read how pointing draws."
    public static let switches = ["On", "Off"]

    /// True for a direct ask about the trail and the screenshot. The pointing keys are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "pointing", "trail", "set"], ["does", "pointing", "draw", "while", "held"],
             ["does", "pointing", "send", "a", "screenshot"], ["can", "i", "type", "a", "pointing", "question"],
             ["pointing", "trail", "settings"], ["is", "the", "pointing", "trail", "on"]:
            return true
        default:
            return false
        }
    }

    /// Four known switches use that sentence. Anything else is unread.
    public static func line(point: String, ink: String, shot: String, type: String) -> String {
        guard known(point: point, ink: ink, shot: shot, type: type) else { return unread }
        return "\(pointLine(point)), \(inkLine(ink)), \(shotLine(shot)), and \(typeLine(type))."
    }

    public static func known(point: String, ink: String, shot: String, type: String) -> Bool {
        switches.contains(point) && switches.contains(ink) && switches.contains(shot) && switches.contains(type)
    }

    private static func pointLine(_ value: String) -> String {
        value == "On" ? "Pointing is on" : "Pointing is off"
    }

    private static func inkLine(_ value: String) -> String {
        value == "On" ? "the trail while held is on" : "the trail while held is off"
    }

    private static func shotLine(_ value: String) -> String {
        value == "On" ? "screenshots go with each question" : "screenshots stay off"
    }

    private static func typeLine(_ value: String) -> String {
        value == "On" ? "typed questions are on" : "typed questions are off"
    }

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

public struct PointTrailDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown switch draws Can't. Otherwise Trail, then pointing, the ink, the screenshot, and typed questions.
    public static func plan(point: String, ink: String, shot: String, type: String) -> PointTrailDraw {
        guard PointTrailAsk.known(point: point, ink: ink, shot: shot, type: type) else { return make(lines: ["Can't"]) }
        return make(lines: ["Point: \(point)", "Ink: \(ink)", "Shot: \(shot)", "Type: \(type)"])
    }

    /// The short line beside the bolt. The first beat says Trail.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Trail" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Trail"
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

    private static func make(lines: [String]) -> PointTrailDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Trail"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PointTrailDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
