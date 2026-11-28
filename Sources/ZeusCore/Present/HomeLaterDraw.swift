import Foundation

/// A spoken check of the world clock and the countdown, and the cards drawn while Zeus answers it.
///
/// Whether the cities are the defaults, whether a countdown title is set, and the countdown day.
/// The title and the city list stay off the card. Which Home cards show stays its own ask.
public enum HomeLaterAsk {
    public static let unread = "I can't read the world clock or the countdown."
    public static let cities = ["None", "Default", "Custom"]
    public static let titles = ["None", "Set"]
    public static let defaultCities = "Europe/London, America/New_York, Asia/Tokyo"

    /// True for a direct ask about these fields. How many days are left is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "world", "clock", "set"], ["which", "world", "clock", "cities"],
             ["how", "is", "the", "countdown", "set"], ["countdown", "settings"],
             ["what", "is", "the", "countdown", "day"], ["when", "is", "the", "countdown"]:
            return true
        default:
            return false
        }
    }

    /// A known city choice, title choice, and day use that sentence. Anything else is unread.
    public static func line(cities: String, title: String, day: String) -> String {
        guard known(cities: cities, title: title, day: day) else { return unread }
        return "The world clock \(clocks(cities)), the countdown \(titled(title)), and \(dated(day))."
    }

    public static func known(cities: String, title: String, day: String) -> Bool {
        self.cities.contains(cities) && titles.contains(title) && knownDay(day)
    }

    /// None, or a year-month-day from 2000 through 2099.
    public static func knownDay(_ day: String) -> Bool {
        if day == "None" { return true }
        let parts = day.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let date = Int(parts[2]),
              (2000...2099).contains(year), (1...12).contains(month), (1...31).contains(date)
        else { return false }
        return day == String(format: "%04d-%02d-%02d", year, month, date)
    }

    private static func clocks(_ cities: String) -> String {
        switch cities {
        case "Default": "uses the default cities"
        case "Custom": "uses your own cities"
        default: "has no cities"
        }
    }

    private static func titled(_ title: String) -> String {
        title == "Set" ? "has a title" : "has no title"
    }

    private static func dated(_ day: String) -> String {
        day == "None" ? "it has no day" : "the day is \(day)"
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        folded = folded.replacingOccurrences(of: "when's", with: "when is")
        folded = folded.replacingOccurrences(of: "whens", with: "when is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct HomeLaterDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Later, then the cities, the title, and the day.
    public static func plan(cities: String, title: String, day: String) -> HomeLaterDraw {
        guard HomeLaterAsk.known(cities: cities, title: title, day: day) else { return make(lines: ["Can't"]) }
        return make(lines: ["Cities: \(cities)", "Title: \(title)", "Day: \(day)"])
    }

    /// The short line beside the bolt. The first beat says Later.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Later" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Later"
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

    private static func make(lines: [String]) -> HomeLaterDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Later"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return HomeLaterDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
