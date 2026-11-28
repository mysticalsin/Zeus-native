import Foundation

/// A spoken check of the second brain, and the cards drawn while Zeus answers it.
///
/// Whether a vault is connected, and whether access is read only or read and write.
/// The vault name and the path stay off the card. Nothing is connected or disconnected.
public enum BrainSetupAsk {
    public static let unread = "I can't read the second brain."
    public static let links = ["None", "Set"]
    public static let doors = ["None", "Read", "Write"]

    /// True for a direct ask about the second brain. To-do settings are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "second", "brain", "set"], ["is", "a", "vault", "connected"],
             ["memory", "settings"], ["is", "the", "vault", "read", "only"],
             ["how", "is", "memory", "set"], ["which", "vault", "access"]:
            return true
        default:
            return false
        }
    }

    /// A known link and a known access use that sentence. Anything else is unread.
    public static func line(link: String, access: String) -> String {
        guard known(link: link, access: access) else { return unread }
        let vault = link == "Set" ? "A vault is connected" : "No vault is connected"
        return "\(vault), and \(door(access))."
    }

    public static func known(link: String, access: String) -> Bool {
        links.contains(link) && doors.contains(access)
    }

    private static func door(_ access: String) -> String {
        switch access {
        case "Read": "access is read only"
        case "Write": "access is read and write"
        default: "access is not set"
        }
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

public struct BrainSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Brain, then the link and the access.
    public static func plan(link: String, access: String) -> BrainSetupDraw {
        guard BrainSetupAsk.known(link: link, access: access) else { return make(lines: ["Can't"]) }
        return make(lines: ["Link: \(link)", "Access: \(access)"])
    }

    /// The short line beside the bolt. The first beat says Brain.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Brain" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Brain"
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

    private static func make(lines: [String]) -> BrainSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Brain"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return BrainSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
