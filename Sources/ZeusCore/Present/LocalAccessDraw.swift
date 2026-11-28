import Foundation

/// A spoken check of location, Full Disk Access, and key access, and the cards drawn while Zeus answers it.
///
/// Location and Full Disk Access are allowed or off. Keys are Accessibility, Input Monitoring, or not allowed.
/// Calendar, reminders, and the microphone stay their own asks. Nothing is requested.
public enum LocalAccessAsk {
    public static let unread = "I can't read location, disk, or key access."
    public static let flags = ["Allowed", "Off"]
    /// The same words as the Keys from other apps row.
    public static let keys = ["Accessibility", "Input Monitoring", "Not allowed"]

    /// True for a direct ask about these three. The other permission packs are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "location", "set"], ["is", "full", "disk", "access", "on"],
             ["which", "key", "access"], ["local", "permission", "settings"],
             ["is", "location", "allowed"], ["can", "zeus", "read", "other", "keys"]:
            return true
        default:
            return false
        }
    }

    /// Three known choices use that sentence. Anything else is unread.
    public static func line(place: String, disk: String, keys: String) -> String {
        guard known(place: place, disk: disk, keys: keys) else { return unread }
        let where_ = place == "Allowed" ? "Location is allowed" : "Location is off"
        let files = disk == "Allowed" ? "Full Disk Access is allowed" : "Full Disk Access is off"
        let seen: String
        switch keys {
        case "Accessibility": seen = "keys are seen through Accessibility"
        case "Input Monitoring": seen = "keys are seen through Input Monitoring"
        default: seen = "keys are not allowed"
        }
        return "\(where_), \(files), and \(seen)."
    }

    public static func known(place: String, disk: String, keys: String) -> Bool {
        flags.contains(place) && flags.contains(disk) && Self.keys.contains(keys)
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

public struct LocalAccessDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Local, then location, disk, and keys.
    public static func plan(place: String, disk: String, keys: String) -> LocalAccessDraw {
        guard LocalAccessAsk.known(place: place, disk: disk, keys: keys) else { return make(lines: ["Can't"]) }
        return make(lines: ["Place: \(place)", "Disk: \(disk)", "Keys: \(keys)"])
    }

    /// The short line beside the bolt. The first beat says Local.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Local" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Local"
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

    private static func make(lines: [String]) -> LocalAccessDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Local"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return LocalAccessDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
