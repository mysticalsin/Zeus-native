import Foundation

/// A spoken check of displays without a notch, and the cards drawn while Zeus answers it.
///
/// Pill or Notch, and whether that shape is shown, not shown, or there is no such display.
/// Where the notch is placed stays its own ask. The shape is not changed and calibration is not started.
public enum NotchlessAsk {
    public static let unread = "I can't read the notchless shape."
    /// The same titles as the Shape control.
    public static let shapes = ["Pill", "Notch"]
    /// Shown, not shown on that display, or no display without a notch.
    public static let sees = ["Shown", "Not shown", "No display"]

    /// True for a direct ask about the notchless shape. Where the notch is placed is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "notchless", "shape"], ["which", "shape", "without", "a", "notch"],
             ["notchless", "display", "settings"], ["what", "is", "the", "drawn", "notch"],
             ["is", "the", "drawn", "notch", "shown"], ["pill", "or", "notch"]:
            return true
        default:
            return false
        }
    }

    /// A known shape and a known place use that sentence. Anything else is unread.
    public static func line(shape: String, see: String) -> String {
        guard known(shape: shape, see: see) else { return unread }
        let drawn = shape == "Notch" ? "a Notch" : "a Pill"
        let place: String
        switch see {
        case "Shown": place = "it is shown"
        case "Not shown": place = "it is not shown on that display"
        default: place = "there is no display without a notch"
        }
        return "Displays without a notch draw \(drawn), and \(place)."
    }

    public static func known(shape: String, see: String) -> Bool {
        shapes.contains(shape) && sees.contains(see)
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

public struct NotchlessDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Shape, then Pill or Notch and whether it is shown.
    public static func plan(shape: String, see: String) -> NotchlessDraw {
        guard NotchlessAsk.known(shape: shape, see: see) else { return make(lines: ["Can't"]) }
        return make(lines: ["Shape: \(shape)", "See: \(see)"])
    }

    /// The short line beside the bolt. The first beat says Shape.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Shape" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Shape"
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

    private static func make(lines: [String]) -> NotchlessDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Shape"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return NotchlessDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
