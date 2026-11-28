import Foundation

/// A spoken check of the usage meter, and the cards drawn while Zeus answers it.
///
/// The meter compares with the busiest window, or with a limit already set. Alerts are on or off.
/// Today's tokens and the dollar cost stay their own ask. Nothing is scanned.
public enum UsageMeterAsk {
    public static let unread = "I can't read the usage meter."
    public static let meters = ["Busiest", "Custom"]
    public static let alerts = ["On", "Off"]

    /// True for a direct ask about the usage meter. Today's tokens are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "usage", "meter", "set"], ["are", "usage", "alerts", "on"],
             ["usage", "meter", "settings"], ["does", "the", "usage", "meter", "use", "a", "limit"],
             ["is", "the", "usage", "meter", "the", "busiest", "window"], ["how", "are", "usage", "alerts", "set"]:
            return true
        default:
            return false
        }
    }

    /// A known meter and a known alert switch use that sentence. Anything else is unread.
    public static func line(meter: String, alerts: String) -> String {
        guard known(meter: meter, alerts: alerts) else { return unread }
        let compare = meter == "Custom" ? "a limit you set" : "your busiest window"
        let notice = alerts == "On" ? "on" : "off"
        return "The usage meter uses \(compare), and limit alerts are \(notice)."
    }

    public static func known(meter: String, alerts: String) -> Bool {
        meters.contains(meter) && self.alerts.contains(alerts)
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

public struct UsageMeterDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown meter draws Can't. Otherwise Usage, then the comparison and the alerts.
    public static func plan(meter: String, alerts: String) -> UsageMeterDraw {
        guard UsageMeterAsk.known(meter: meter, alerts: alerts) else { return make(lines: ["Can't"]) }
        return make(lines: ["Meter: \(meter)", "Alerts: \(alerts)"])
    }

    /// The short line beside the bolt. The first beat says Usage.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Usage" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Usage"
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

    private static func make(lines: [String]) -> UsageMeterDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Usage"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return UsageMeterDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
