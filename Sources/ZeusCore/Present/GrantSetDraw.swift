import Foundation

/// A spoken check of three permissions, and the cards drawn while Zeus answers it.
///
/// Accessibility, Calendar, and Reminders: allowed, or off. Microphone, speech, the camera,
/// and screen recording stay their own asks. Nothing is requested.
public enum GrantSetAsk {
    public static let unread = "I can't read those permissions."
    public static let states = ["Allowed", "Off"]

    /// True for a direct ask about these three. Voice permissions and screen recording are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "other", "permissions"], ["how", "is", "accessibility", "set"],
             ["other", "permission", "settings"], ["are", "reminders", "allowed"],
             ["is", "the", "calendar", "allowed"], ["is", "accessibility", "on"]:
            return true
        default:
            return false
        }
    }

    /// Three known states use that sentence. Anything else is unread.
    public static func line(access: String, calendar: String, reminders: String) -> String {
        guard known(access: access, calendar: calendar, reminders: reminders) else { return unread }
        return "\(bit("Accessibility", access)), \(bit("the calendar", calendar)), and \(reminders == "Allowed" ? "reminders are allowed" : "reminders are off")."
    }

    public static func known(access: String, calendar: String, reminders: String) -> Bool {
        states.contains(access) && states.contains(calendar) && states.contains(reminders)
    }

    private static func bit(_ name: String, _ value: String) -> String {
        value == "Allowed" ? "\(name) is allowed" : "\(name) is off"
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

public struct GrantSetDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown states draw Can't. Otherwise Grant, then Accessibility, Calendar, and Reminders.
    public static func plan(access: String, calendar: String, reminders: String) -> GrantSetDraw {
        guard GrantSetAsk.known(access: access, calendar: calendar, reminders: reminders) else { return make(lines: ["Can't"]) }
        return make(lines: ["Access: \(access)", "Calendar: \(calendar)", "Reminders: \(reminders)"])
    }

    /// The short line beside the bolt. The first beat says Grant.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Grant" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Grant"
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

    private static func make(lines: [String]) -> GrantSetDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Grant"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return GrantSetDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
