import Foundation

/// A spoken check of the agent picker shortcut and keyboard answers, and the cards drawn while Zeus answers it.
///
/// The picker key is one of the six Shortcuts titles. Keyboard answers are on or off.
/// The chat shortcut stays its own ask. Nothing is registered or changed.
public enum PickerSetupAsk {
    public static let unread = "I can't read the agent picker shortcut."
    public static let switches = ["On", "Off"]
    /// The same titles as the Open the agent picker menu.
    public static let opens = ["Off", "⌃⌥ Space", "⌥⌘ Z", "⌃⌘ Z", "⌃⌥ T", "⌥⌘ T"]

    /// True for a direct ask about the agent picker or keyboard answers. The chat shortcut is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["what", "is", "the", "agent", "picker", "shortcut"], ["which", "agent", "picker", "key"],
             ["how", "is", "the", "agent", "picker", "set"], ["agent", "picker", "settings"],
             ["can", "i", "answer", "from", "the", "keyboard"], ["are", "answer", "keys", "on"]:
            return true
        default:
            return false
        }
    }

    /// A known answer switch and a known picker key use that sentence. Anything else is unread.
    public static func line(answer: String, open: String) -> String {
        guard known(answer: answer, open: open) else { return unread }
        let keys = answer == "On" ? "Keyboard answers are on" : "Keyboard answers are off"
        return "\(keys), and \(picker(open))."
    }

    public static func known(answer: String, open: String) -> Bool {
        switches.contains(answer) && opens.contains(open)
    }

    private static func picker(_ title: String) -> String {
        switch title {
        case "Off": "the agent picker shortcut is off"
        case "⌃⌥ Space": "the agent picker opens with Control, Option, and Space"
        case "⌥⌘ Z": "the agent picker opens with Option, Command, and Z"
        case "⌃⌘ Z": "the agent picker opens with Control, Command, and Z"
        case "⌃⌥ T": "the agent picker opens with Control, Option, and T"
        default: "the agent picker opens with Option, Command, and T"
        }
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

public struct PickerSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Picker, then keyboard answers and the picker key.
    public static func plan(answer: String, open: String) -> PickerSetupDraw {
        guard PickerSetupAsk.known(answer: answer, open: open) else { return make(lines: ["Can't"]) }
        return make(lines: ["Answer: \(answer)", "Open: \(open)"])
    }

    /// The short line beside the bolt. The first beat says Picker.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Picker" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Picker"
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

    private static func make(lines: [String]) -> PickerSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Picker"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PickerSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
