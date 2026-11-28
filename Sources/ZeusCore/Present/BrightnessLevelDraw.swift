import Foundation

/// A spoken brightness ask, and the cards drawn while Zeus answers it.
///
/// The voice says the level. The screen builds Brightness, then the percent, then Dim or Bright.
/// A dark screen shows Brightness, then Off. The volume stays on its own card.
public enum BrightnessLevelAsk {
    public static let unread = "I can't read the brightness."
    /// At or below this, the third card says Dim.
    public static let dimAt = 20

    /// True for a direct ask about the screen brightness. The volume, and a change, are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["brightness"], ["the", "brightness"], ["my", "brightness"], ["screen", "brightness"],
             ["the", "screen", "brightness"], ["display", "brightness"], ["the", "display", "brightness"],
             ["what", "is", "the", "brightness"], ["what", "is", "my", "brightness"], ["what", "the", "brightness"],
             ["how", "is", "the", "brightness"], ["how", "is", "my", "brightness"],
             ["how", "bright"], ["how", "bright", "is", "it"], ["how", "bright", "is", "the", "screen"],
             ["how", "bright", "is", "the", "display"], ["current", "brightness"],
             ["what", "is", "the", "screen", "brightness"], ["what", "is", "the", "current", "brightness"]:
            return true
        default:
            return false
        }
    }

    /// 0...100, or nil when the level is not a real fraction of full.
    public static func percent(of level: Double) -> Int? {
        guard level.isFinite else { return nil }
        let value = Int((min(1, max(0, level)) * 100).rounded())
        guard (0...100).contains(value) else { return nil }
        return value
    }

    /// Nil when the percent is outside 0...100. Zero says the screen is dark.
    public static func line(percent: Int) -> String? {
        guard (0...100).contains(percent) else { return nil }
        if percent == 0 { return "The screen is dark." }
        return "Brightness is at \(percent) percent."
    }

    /// Dim at or below `dimAt`. Bright above that. Off is reserved for zero.
    public static func state(percent: Int) -> String {
        if percent <= 0 { return "Off" }
        if percent <= dimAt { return "Dim" }
        return "Bright"
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

public struct BrightnessLevelDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var level: String
    public var state: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, level: String, state: String) {
        self.draw = draw
        self.schedule = schedule
        self.level = level
        self.state = state
    }

    /// Nil when the percent is outside 0...100. Zero draws Brightness, then Off.
    public static func plan(percent: Int) -> BrightnessLevelDraw? {
        guard BrightnessLevelAsk.line(percent: percent) != nil else { return nil }
        let state = BrightnessLevelAsk.state(percent: percent)
        if percent == 0 { return make(lines: ["Off"], level: "", state: state) }
        let level = "\(percent)%"
        return make(lines: [level, state], level: level, state: state)
    }

    /// Brightness, then Can't.
    public static func unread() -> BrightnessLevelDraw { make(lines: ["Can't"], level: "", state: "") }

    /// The short line beside the bolt. The first beat says Brightness.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Brightness" }
        if last >= 2, !state.isEmpty { return state }
        if !level.isEmpty { return level }
        return stateWord
    }

    private var stateWord: String {
        for mark in draw.marks {
            if case .card(_, let text) = mark.shape, text != "Brightness" { return text }
        }
        return "Can't"
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

    private static func make(lines: [String], level: String, state: String) -> BrightnessLevelDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Brightness"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return BrightnessLevelDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), level: level, state: state)
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
