import Foundation

/// A spoken check of how Fling is set, and the cards drawn while Zeus answers it.
///
/// Whether it is on, who can see this Mac, and where arrivals go.
/// The files on the Shelf stay their own ask. The Mac's name stays off the card.
public enum FlingSetupAsk {
    public static let unread = "I can't read how Fling is set."
    public static let works = ["On", "Off"]
    /// The same labels as the Who can see this Mac menu.
    public static let sees = ["Everyone nearby", "Paired only", "Off"]
    /// The same labels as the Where arrivals go menu.
    public static let saves = ["Downloads/Fling", "Clipboard", "Ask each time"]

    /// True for a direct ask about the Fling setup. The files on the Shelf are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "fling", "set"], ["which", "fling", "settings"],
             ["fling", "settings"], ["who", "can", "see", "this", "mac"],
             ["where", "do", "fling", "arrivals", "go"], ["how", "is", "the", "shelf", "set"]:
            return true
        default:
            return false
        }
    }

    /// Three known choices use that sentence. Anything else is unread.
    public static func line(work: String, see: String, save: String) -> String {
        guard known(work: work, see: see, save: save) else { return unread }
        let state = work == "On" ? "on" : "off"
        return "Fling is \(state), shows \(see), and arrivals use \(save)."
    }

    public static func known(work: String, see: String, save: String) -> Bool {
        works.contains(work) && sees.contains(see) && saves.contains(save)
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
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

public struct FlingSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Fling, then work, who can see it, and where arrivals go.
    public static func plan(work: String, see: String, save: String) -> FlingSetupDraw {
        guard FlingSetupAsk.known(work: work, see: see, save: save) else { return make(lines: ["Can't"]) }
        return make(lines: ["Work: \(work)", "See: \(see)", "Save: \(save)"])
    }

    /// The short line beside the bolt. The first beat says Fling.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Fling" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Fling"
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

    private static func make(lines: [String]) -> FlingSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Fling"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return FlingSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
