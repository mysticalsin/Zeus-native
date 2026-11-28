import Foundation

/// A spoken check of shelf verification and stacks, and the cards drawn while Zeus answers it.
///
/// Verified is how many files matched their sender. Stacks are groups of two or more files.
/// File names, and how many files are on the shelf, stay their own ask. Nothing is moved.
public enum ShelfStackAsk {
    public static let unread = "I can't read the shelf stacks."

    /// True for a direct ask about verified files or stacks. The file names are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "many", "shelf", "files", "are", "verified"], ["how", "many", "shelf", "stacks", "are", "there"],
             ["shelf", "verification", "settings"], ["are", "any", "shelf", "files", "verified"],
             ["how", "are", "shelf", "stacks", "set"], ["is", "a", "shelf", "stack", "grouped"]:
            return true
        default:
            return false
        }
    }

    /// Two counts from 0 to 999 use that sentence. Anything else is unread.
    public static func line(verified: String, stacks: String) -> String {
        guard let files = knownCount(verified), let groups = knownCount(stacks) else { return unread }
        return "\(verifiedWord(files)), and \(stackWord(groups))."
    }

    public static func known(verified: String, stacks: String) -> Bool {
        knownCount(verified) != nil && knownCount(stacks) != nil
    }

    private static func knownCount(_ value: String) -> Int? {
        guard let number = Int(value), (0...999).contains(number), String(number) == value else { return nil }
        return number
    }

    private static func verifiedWord(_ count: Int) -> String {
        switch count {
        case 0: "No shelf files are verified"
        case 1: "1 shelf file is verified"
        default: "\(count) shelf files are verified"
        }
    }

    private static func stackWord(_ count: Int) -> String {
        switch count {
        case 0: "there are no stacks"
        case 1: "there is 1 stack"
        default: "there are \(count) stacks"
        }
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

public struct ShelfStackDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// A bad count draws Can't. Otherwise Stacks, then verified files and stack groups.
    public static func plan(verified: String, stacks: String) -> ShelfStackDraw {
        guard ShelfStackAsk.known(verified: verified, stacks: stacks) else { return make(lines: ["Can't"]) }
        return make(lines: ["Verified: \(verified)", "Stacks: \(stacks)"])
    }

    /// The short line beside the bolt. The first beat says Stacks.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Stacks" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Stacks"
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

    private static func make(lines: [String]) -> ShelfStackDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Stacks"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ShelfStackDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
