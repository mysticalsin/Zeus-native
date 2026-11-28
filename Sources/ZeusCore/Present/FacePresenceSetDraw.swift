import Foundation

/// A spoken check of the face-presence settings, and the cards drawn while Zeus answers it.
///
/// Whether the switch is on, and how long an enrolled face may be absent before the Mac locks.
/// Whether you are present right now stays its own ask. This does not turn the camera on or lock the Mac.
public enum FacePresenceSetAsk {
    public static let unread = "I can't read the face presence settings."
    public static let switches = ["On", "Off"]
    /// The same titles as Lock after absent for.
    public static let waits = ["30 seconds", "1 minute", "2 minutes", "5 minutes", "10 minutes"]

    /// True for a direct ask about the face-presence settings. Being present is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "face", "presence", "set"], ["face", "presence", "settings"],
             ["which", "lock", "after"], ["when", "is", "the", "face", "lock"],
             ["how", "long", "until", "face", "presence", "locks"], ["how", "is", "the", "face", "lock", "set"]:
            return true
        default:
            return false
        }
    }

    /// A known switch and a known wait use that sentence. Anything else is unread.
    public static func line(work: String, wait: String) -> String {
        guard known(work: work, wait: wait) else { return unread }
        return "Face presence is \(word(work)), and it locks after you have been absent for \(wait)."
    }

    public static func known(work: String, wait: String) -> Bool {
        switches.contains(work) && waits.contains(wait)
    }

    private static func word(_ value: String) -> String { value == "On" ? "on" : "off" }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
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

public struct FacePresenceSetDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Absent, then the switch and the lock wait.
    public static func plan(work: String, wait: String) -> FacePresenceSetDraw {
        guard FacePresenceSetAsk.known(work: work, wait: wait) else { return make(lines: ["Can't"]) }
        return make(lines: ["Work: \(work)", "Wait: \(wait)"])
    }

    /// The short line beside the bolt. The first beat says Absent.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Absent" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Absent"
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

    private static func make(lines: [String]) -> FacePresenceSetDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Absent"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return FacePresenceSetDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
