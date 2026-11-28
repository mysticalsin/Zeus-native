import Foundation

/// A spoken check of the saved drawn-notch size, and the cards drawn while Zeus answers it.
///
/// Width, height, and sideways position. The pill or notch choice stays its own ask.
/// Calibration is not started and the shape is not changed.
public enum DrawnSizeAsk {
    public static let unread = "I can't read the drawn notch size."

    /// True for a direct ask about the size. The shape and where the notch shows are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "big", "is", "the", "drawn", "notch"], ["how", "is", "the", "drawn", "notch", "sized"],
             ["where", "does", "the", "drawn", "notch", "sit"], ["drawn", "notch", "size", "settings"],
             ["how", "wide", "is", "the", "drawn", "notch"], ["how", "tall", "is", "the", "drawn", "notch"]:
            return true
        default:
            return false
        }
    }

    /// A width on its step, a height in range, and a known place use that sentence. Anything else is unread.
    public static func line(width: String, height: String, place: String) -> String {
        guard known(width: width, height: height, place: place) else { return unread }
        return "The drawn notch is \(width) points wide, \(height) points tall, and \(placeLine(place))."
    }

    public static func known(width: String, height: String, place: String) -> Bool {
        knownWidth(width) && knownHeight(height) && knownPlace(place)
    }

    private static func knownWidth(_ value: String) -> Bool {
        guard let number = Int(value), (140...280).contains(number), number.isMultiple(of: 5), String(number) == value else { return false }
        return true
    }

    private static func knownHeight(_ value: String) -> Bool {
        guard let number = Int(value), (30...44).contains(number), String(number) == value else { return false }
        return true
    }

    /// "Centre", or a step of 5 from 5 to 400 points to the left or the right.
    private static func knownPlace(_ value: String) -> Bool {
        if value == "Centre" { return true }
        let parts = value.split(separator: " ").map(String.init)
        guard parts.count == 3, parts[1] == "pt", parts[2] == "left" || parts[2] == "right",
              let number = Int(parts[0]), (5...400).contains(number), number.isMultiple(of: 5), String(number) == parts[0] else { return false }
        return true
    }

    private static func placeLine(_ value: String) -> String {
        if value == "Centre" { return "centred" }
        let parts = value.split(separator: " ")
        let side = parts.count == 3 && parts[2] == "left" ? "left" : "right"
        return "\(parts.first ?? "") points to the \(side)"
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
        folded = folded.replacingOccurrences(of: "where's", with: "where is")
        folded = folded.replacingOccurrences(of: "wheres", with: "where is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct DrawnSizeDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown measure draws Can't. Otherwise Size, then the width, the height, and the place.
    public static func plan(width: String, height: String, place: String) -> DrawnSizeDraw {
        guard DrawnSizeAsk.known(width: width, height: height, place: place) else { return make(lines: ["Can't"]) }
        return make(lines: ["Wide: \(width)", "Tall: \(height)", "Place: \(place)"])
    }

    /// The short line beside the bolt. The first beat says Size.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Size" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Size"
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

    private static func make(lines: [String]) -> DrawnSizeDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Size"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return DrawnSizeDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
