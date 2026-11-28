import Foundation

/// The wall clock, drawn while Zeus says the time.
///
/// The voice says the full line. The screen builds Clock, then the digits, then AM or PM.
/// A meeting time and the next event stay on their own cards.
public enum ClockAsk {
    /// True for a direct ask about the clock on the wall. "What time is the meeting" is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["what", "time", "is", "it"],
             ["what", "time", "is", "it", "right", "now"],
             ["what", "time", "is", "it", "now"],
             ["what", "is", "the", "time"],
             ["what", "is", "the", "time", "right", "now"],
             ["what", "is", "the", "time", "now"],
             ["tell", "me", "the", "time"],
             ["tell", "me", "what", "time", "it", "is"],
             ["do", "you", "have", "the", "time"],
             ["have", "you", "got", "the", "time"],
             ["current", "time"]:
            return true
        default:
            return false
        }
    }

    /// "2:47" and "PM". Hour 0 and 12 are both 12.
    public static func parts(now: Date, timeZone: TimeZone) -> (time: String, period: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let hour24 = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let period = hour24 < 12 ? "AM" : "PM"
        return (String(format: "%d:%02d", hour12, minute), period)
    }

    /// Nil when the time or the period is not a wall-clock reading.
    public static func line(time: String, period: String) -> String? {
        guard let time = clockTime(time), let period = dayPeriod(period) else { return nil }
        return "It's \(time) \(period)."
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        let raw = folded.split { !$0.isLetter && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        return words
    }

    static func clockTime(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: ":")
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]),
              (1...12).contains(hour), (0...59).contains(minute), pieces[1].count == 2 else { return nil }
        return String(format: "%d:%02d", hour, minute)
    }

    static func dayPeriod(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "AM": return "AM"
        case "PM": return "PM"
        default: return nil
        }
    }
}

public struct ClockDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var time: String
    public var period: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, time: String, period: String) {
        self.draw = draw
        self.schedule = schedule
        self.time = time
        self.period = period
    }

    /// Nil when the time is not a wall-clock reading, or the period is not AM or PM.
    public static func plan(time: String, period: String) -> ClockDraw? {
        guard let time = ClockAsk.clockTime(time), let period = ClockAsk.dayPeriod(period) else { return nil }
        return make(time: time, period: period)
    }

    /// The short line beside the bolt. The first beat says Clock.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Clock" }
        if last >= 2 { return period }
        return time
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

    private static func make(time: String, period: String) -> ClockDraw {
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Clock"), at: 0),
            .init(shape: .card(origin: .init(x: 920, y: 180), text: time), at: 1),
            .init(shape: .card(origin: .init(x: 920, y: 250), text: period), at: 2),
        ]
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ClockDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), time: time, period: period)
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
