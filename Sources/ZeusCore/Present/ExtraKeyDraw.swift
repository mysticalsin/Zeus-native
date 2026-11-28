import Foundation

/// A spoken check of the second talk key and the dictation shortcut, and the cards drawn while Zeus answers it.
///
/// Right Option or off or a key you chose, and Right Command or off or a key you chose.
/// The main talk key and the chat shortcut stay their own asks. Nothing is recorded.
public enum ExtraKeyAsk {
    public static let unread = "I can't read the second talk key."
    public static let keys = ["Default", "Off", "Chosen"]

    /// True for a direct ask about the second talk key or the dictation shortcut. The main talk key is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["what", "is", "the", "second", "talk", "key"], ["is", "the", "second", "talk", "key", "on"],
             ["what", "is", "the", "dictation", "shortcut"], ["second", "talk", "settings"],
             ["how", "is", "the", "second", "talk", "key", "set"], ["is", "dictations", "shortcut", "the", "default"]:
            return true
        default:
            return false
        }
    }

    /// Two known keys use that sentence. Anything else is unread.
    public static func line(second: String, dictate: String) -> String {
        guard known(second: second, dictate: dictate) else { return unread }
        return "\(secondLine(second)), and \(dictateLine(dictate))."
    }

    public static func known(second: String, dictate: String) -> Bool {
        keys.contains(second) && keys.contains(dictate)
    }

    private static func secondLine(_ value: String) -> String {
        switch value {
        case "Off": "The second talk key is off"
        case "Chosen": "The second talk key is one you chose"
        default: "The second talk key is Right Option"
        }
    }

    private static func dictateLine(_ value: String) -> String {
        switch value {
        case "Off": "dictation has no shortcut"
        case "Chosen": "dictation uses a shortcut you chose"
        default: "dictation uses the right Command key"
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

public struct ExtraKeyDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Extra, then the second talk key and dictation.
    public static func plan(second: String, dictate: String) -> ExtraKeyDraw {
        guard ExtraKeyAsk.known(second: second, dictate: dictate) else { return make(lines: ["Can't"]) }
        return make(lines: ["Second: \(second)", "Dictate: \(dictate)"])
    }

    /// The short line beside the bolt. The first beat says Extra.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Extra" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Extra"
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

    private static func make(lines: [String]) -> ExtraKeyDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Extra"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ExtraKeyDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
