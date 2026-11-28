import Foundation

/// A spoken check of the reminder chips, and the cards drawn while Zeus answers it.
///
/// The list is Today, Scheduled, All, or Flagged. A due chip may be waiting for the next reminder.
/// The next reminder's words stay their own ask. Nothing is added or completed.
public enum ReminderListAsk {
    public static let unread = "I can't read the reminder list."
    public static let lists = ["Today", "Scheduled", "All", "Flagged"]
    public static let dues = ["None", "In 1 hour", "This evening", "Tomorrow 9:00", "Next week"]

    /// True for a direct ask about the reminder chips. The next reminder is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "reminders", "are", "showing"], ["how", "is", "the", "reminder", "list", "set"],
             ["reminder", "list", "settings"], ["is", "a", "due", "time", "waiting"],
             ["which", "reminder", "filter"], ["what", "reminder", "list", "is", "open"]:
            return true
        default:
            return false
        }
    }

    /// A known list and a known due chip use that sentence. Anything else is unread.
    public static func line(list: String, due: String) -> String {
        guard known(list: list, due: due) else { return unread }
        return "Reminders are showing \(list), and \(dueWord(due))."
    }

    public static func known(list: String, due: String) -> Bool {
        lists.contains(list) && dues.contains(due)
    }

    private static func dueWord(_ due: String) -> String {
        switch due {
        case "In 1 hour": "the next one is due in an hour"
        case "This evening": "the next one is due this evening"
        case "Tomorrow 9:00": "the next one is due tomorrow at 9"
        case "Next week": "the next one is due next week"
        default: "no due time is waiting"
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

public struct ReminderListDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown chip draws Can't. Otherwise Lists, then the list and the due chip.
    public static func plan(list: String, due: String) -> ReminderListDraw {
        guard ReminderListAsk.known(list: list, due: due) else { return make(lines: ["Can't"]) }
        return make(lines: ["List: \(list)", "Due: \(due)"])
    }

    /// The short line beside the bolt. The first beat says Lists.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Lists" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Lists"
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

    private static func make(lines: [String]) -> ReminderListDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Lists"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ReminderListDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
