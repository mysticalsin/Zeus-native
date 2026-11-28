import Foundation

/// A spoken check of when Scribe starts, and the cards drawn while Zeus answers it.
///
/// Off, ask first, or start on its own, and whether anything is holding an automatic start.
/// A meeting is not started, and the microphone is not requested.
public enum ScribeSetupAsk {
    public static let unread = "I can't read when a meeting starts."
    /// The same titles as When a meeting starts.
    public static let starts = ["Off", "Ask me", "Start automatically"]
    /// Clear means nothing to fix. The others are the holds the Scribe card can show.
    public static let holds = ["Clear", "Not yet", "Denied", "Once"]

    /// True for a direct ask about the Scribe setting. A recording that is already going is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "scribe", "set"], ["when", "a", "meeting", "starts"],
             ["scribe", "settings"], ["how", "is", "meeting", "start", "set"],
             ["which", "scribe", "start"], ["does", "scribe", "start", "automatically"]:
            return true
        default:
            return false
        }
    }

    /// A known start and a known hold use that sentence. Anything else is unread.
    public static func line(start: String, hold: String) -> String {
        guard known(start: start, hold: hold) else { return unread }
        let action: String
        switch start {
        case "Off": action = "Zeus stays off"
        case "Ask me": action = "Zeus asks you"
        default: action = "Zeus starts on its own"
        }
        let tail: String
        switch hold {
        case "Clear": tail = "nothing is holding an automatic start"
        case "Not yet": tail = "the microphone is not allowed yet"
        case "Denied": tail = "the microphone is off for Zeus"
        default: tail = "automatic start needs one recording first"
        }
        let join = hold == "Clear" ? "and" : "but"
        return "When a meeting starts, \(action), \(join) \(tail)."
    }

    public static func known(start: String, hold: String) -> Bool {
        starts.contains(start) && holds.contains(hold)
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

public struct ScribeSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Meet, then how a meeting starts and what holds it.
    public static func plan(start: String, hold: String) -> ScribeSetupDraw {
        guard ScribeSetupAsk.known(start: start, hold: hold) else { return make(lines: ["Can't"]) }
        return make(lines: ["Start: \(start)", "Hold: \(hold)"])
    }

    /// The short line beside the bolt. The first beat says Meet.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Meet" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Meet"
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

    private static func make(lines: [String]) -> ScribeSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Meet"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ScribeSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
