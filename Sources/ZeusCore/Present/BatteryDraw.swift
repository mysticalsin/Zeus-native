import Foundation

/// A spoken battery ask, and the cards drawn while Zeus answers it.
///
/// The voice says the charge. The screen builds Battery, then Charging, Plugged in,
/// On battery, or Low, then the percent. A Mac with no battery shows None.
public enum BatteryAsk {
    public static let none = "This Mac has no battery."

    public enum State: Equatable, Sendable {
        case charging, pluggedIn, onBattery, low
    }

    /// True for a direct battery ask. A keep-awake command is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["battery"], ["my", "battery"], ["the", "battery"], ["battery", "level"], ["battery", "left"],
             ["what", "my", "battery"], ["what", "is", "my", "battery"], ["what", "the", "battery"],
             ["what", "is", "the", "battery"], ["how", "my", "battery"], ["how", "is", "my", "battery"],
             ["how", "the", "battery"], ["how", "is", "the", "battery"], ["how", "much", "battery"],
             ["how", "much", "battery", "is", "left"], ["how", "much", "charge"]:
            return true
        default:
            return false
        }
    }

    /// Charging wins. A charge at or below 20 that is not charging is low.
    public static func state(level: Int, charging: Bool, pluggedIn: Bool) -> State {
        if charging { return .charging }
        if level <= 20 { return .low }
        if pluggedIn { return .pluggedIn }
        return .onBattery
    }

    public static func line(level: Int, state: State) -> String {
        let percent = "\(level) percent"
        switch state {
        case .charging: return "Charging, \(percent)."
        case .pluggedIn: return "Plugged in, \(percent)."
        case .onBattery: return "On battery, \(percent)."
        case .low: return "Battery is low, \(percent)."
        }
    }

    public static func card(_ state: State) -> String {
        switch state {
        case .charging: "Charging"
        case .pluggedIn: "Plugged in"
        case .onBattery: "On battery"
        case .low: "Low"
        }
    }

    private static func words(in text: String) -> [String] {
        let folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        let raw = folded.split { !$0.isLetter && $0 != "'" }.map { token -> String in
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

public struct BatteryDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var state: String?
    public var percent: String?

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, state: String?, percent: String?) {
        self.draw = draw
        self.schedule = schedule
        self.state = state
        self.percent = percent
    }

    /// Nil when the level is outside 0...100.
    public static func plan(level: Int, state: BatteryAsk.State) -> BatteryDraw? {
        guard (0...100).contains(level) else { return nil }
        let word = BatteryAsk.card(state)
        let percent = "\(level) percent"
        return make(cards: [word, percent], state: word, percent: percent)
    }

    /// Battery, then None.
    public static func none() -> BatteryDraw {
        make(cards: ["None"], state: nil, percent: nil)
    }

    /// The short line beside the bolt. The first beat says Battery.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Battery" }
        if last == 1 { return state ?? "None" }
        return percent ?? state ?? "Battery"
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

    private static func make(cards: [String], state: String?, percent: String?) -> BatteryDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Battery"), at: 0),
        ]
        for (index, text) in cards.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return BatteryDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), state: state, percent: percent)
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
