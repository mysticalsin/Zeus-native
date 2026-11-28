import Foundation

/// A spoken check of the closed notch's drop and the waves' sensitivity, and the cards drawn while Zeus answers it.
///
/// The top bar's drop in points, and how strongly the waves react. Where the notch shows, and the waves style, stay their own asks.
/// Nothing is moved.
public enum NotchFitAsk {
    public static let unread = "I can't read the closed notch."

    /// True for a direct ask about the drop or the waves' sensitivity. The waves style is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "low", "is", "the", "top", "bar"], ["what", "is", "the", "top", "bar", "position"],
             ["how", "sensitive", "are", "the", "waves"], ["how", "is", "the", "closed", "notch", "set"],
             ["appearance", "fit", "settings"], ["what", "is", "the", "waves", "sensitivity"]:
            return true
        default:
            return false
        }
    }

    /// An even drop from 0 to 24 and a sensitivity from 50 to 200 use that sentence. Anything else is unread.
    public static func line(bar: String, waves: String) -> String {
        guard known(bar: bar, waves: waves), let drop = Int(bar), let gain = Int(waves) else { return unread }
        let place = drop == 0 ? "flush with the top" : "\(drop) points lower"
        return "The closed notch is \(place), and the waves react at \(gain)."
    }

    public static func known(bar: String, waves: String) -> Bool {
        knownBar(bar) && knownWaves(waves)
    }

    private static func knownBar(_ bar: String) -> Bool {
        guard let number = Int(bar), (0...24).contains(number), number % 2 == 0, String(number) == bar else { return false }
        return true
    }

    private static func knownWaves(_ waves: String) -> Bool {
        guard let number = Int(waves), (50...200).contains(number), String(number) == waves else { return false }
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

public struct NotchFitDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// A number outside a slider draws Can't. Otherwise Fit, then the drop and the sensitivity.
    public static func plan(bar: String, waves: String) -> NotchFitDraw {
        guard NotchFitAsk.known(bar: bar, waves: waves) else { return make(lines: ["Can't"]) }
        return make(lines: ["Bar: \(bar)", "Waves: \(waves)"])
    }

    /// The short line beside the bolt. The first beat says Fit.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Fit" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Fit"
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

    private static func make(lines: [String]) -> NotchFitDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Fit"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return NotchFitDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
