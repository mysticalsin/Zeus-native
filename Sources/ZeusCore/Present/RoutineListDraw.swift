import Foundation

/// A spoken check of saved routines, and the cards drawn while Zeus answers it.
///
/// How many are saved, and how many are on. Names and prompts stay off the card.
/// A routine that was just saved stays its own ask. Nothing is run or changed.
public enum RoutineListAsk {
    public static let unread = "I can't read the routines."

    /// True for a direct ask about the saved list. A to-do count is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "are", "routines", "set"], ["how", "many", "routines", "are", "saved"],
             ["how", "many", "routines", "are", "on"], ["routine", "list", "settings"],
             ["are", "any", "routines", "on"], ["which", "routines", "are", "turned", "on"]:
            return true
        default:
            return false
        }
    }

    /// Counts from 0 to 999, with the on count no higher than the saved count, use that sentence.
    public static func line(saved: String, on: String) -> String {
        guard known(saved: saved, on: on), let savedCount = Int(saved), let onCount = Int(on) else { return unread }
        if savedCount == 0 { return "No routines are saved." }
        if savedCount == 1 { return onCount == 1 ? "1 routine is saved, and it is on." : "1 routine is saved, and it is off." }
        if onCount == 0 { return "\(savedCount) routines are saved, and none are on." }
        if onCount == 1 { return "\(savedCount) routines are saved, and 1 is on." }
        return "\(savedCount) routines are saved, and \(onCount) are on."
    }

    public static func known(saved: String, on: String) -> Bool {
        guard let savedCount = count(saved), let onCount = count(on), onCount <= savedCount else { return false }
        return true
    }

    private static func count(_ value: String) -> Int? {
        guard let number = Int(value), (0...999).contains(number), String(number) == value else { return nil }
        return number
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

public struct RoutineListDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown count draws Can't. Otherwise Routines, then the saved count and how many are on.
    public static func plan(saved: String, on: String) -> RoutineListDraw {
        guard RoutineListAsk.known(saved: saved, on: on) else { return make(lines: ["Can't"]) }
        return make(lines: ["Saved: \(saved)", "On: \(on)"])
    }

    /// The short line beside the bolt. The first beat says Routines.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Routines" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Routines"
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

    private static func make(lines: [String]) -> RoutineListDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Routines"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return RoutineListDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
