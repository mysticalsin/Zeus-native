import Foundation

/// A spoken check of where Zeus lives, and the cards drawn while Zeus answers it.
///
/// The menu bar icon, and whether dates follow this Mac's calendar.
/// The mascot in the notch and today's date stay their own asks. Nothing is hidden or changed.
public enum LivesAsk {
    public static let unread = "I can't read where Zeus lives."
    public static let switches = ["On", "Off"]
    public static let dates = ["Gregorian", "Mac"]

    /// True for a direct ask about the menu bar icon or the date calendar. Today's date is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["is", "the", "menu", "bar", "icon", "on"], ["which", "calendar", "do", "dates", "use"],
             ["where", "zeus", "lives"], ["menu", "bar", "settings"],
             ["does", "zeus", "follow", "the", "mac", "calendar"], ["how", "is", "the", "menu", "bar", "icon", "set"]:
            return true
        default:
            return false
        }
    }

    /// A known icon and a known calendar use that sentence. Anything else is unread.
    public static func line(menu: String, dates: String) -> String {
        guard known(menu: menu, dates: dates) else { return unread }
        let icon = menu == "On" ? "The menu bar icon is on" : "The menu bar icon is off"
        let calendar = dates == "Mac" ? "dates follow this Mac's calendar" : "dates stay Gregorian"
        return "\(icon), and \(calendar)."
    }

    public static func known(menu: String, dates: String) -> Bool {
        switches.contains(menu) && self.dates.contains(dates)
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

public struct LivesDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Lives, then the icon and the calendar.
    public static func plan(menu: String, dates: String) -> LivesDraw {
        guard LivesAsk.known(menu: menu, dates: dates) else { return make(lines: ["Can't"]) }
        return make(lines: ["Menu: \(menu)", "Dates: \(dates)"])
    }

    /// The short line beside the bolt. The first beat says Lives.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Lives" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Lives"
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

    private static func make(lines: [String]) -> LivesDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Lives"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return LivesDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
