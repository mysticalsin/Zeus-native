import Foundation

/// A spoken check of the talk microphone, and the card drawn while Zeus answers it.
///
/// Automatic, this Mac's microphone, a microphone you chose, or a chosen one that is gone.
/// A device name stays off the card. Dictation's microphone and Hey Zeus stay their own asks.
/// Listening does not start and the choice is not changed.
public enum TalkMicAsk {
    public static let unread = "I can't read the talk microphone."
    /// This Mac's microphone, with the same apostrophe as the menu.
    public static let mac = "This Mac\u{2019}s microphone"
    /// The closed words. A connected device is Chosen. Its name is never spoken.
    public static let hears = ["Automatic", mac, "Chosen", "Unavailable"]

    /// True for a direct ask about the talk microphone. Hey Zeus and dictation are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "talk", "microphone"], ["what", "is", "the", "talk", "microphone"],
             ["how", "is", "the", "talk", "mic", "set"], ["talk", "microphone", "settings"],
             ["which", "mic", "does", "talk", "use"], ["where", "is", "talk", "listening"]:
            return true
        default:
            return false
        }
    }

    /// A known choice uses that sentence. Anything else is unread.
    public static func line(hear: String) -> String {
        guard known(hear: hear) else { return unread }
        switch hear {
        case "Automatic": return "Talk listens on the automatic microphone."
        case mac: return "Talk listens on this Mac's microphone."
        case "Chosen": return "Talk listens on a microphone you chose."
        default: return "The talk microphone you chose is unavailable."
        }
    }

    public static func known(hear: String) -> Bool { hears.contains(hear) }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
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

public struct TalkMicDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Listen, then the microphone.
    public static func plan(hear: String) -> TalkMicDraw {
        guard TalkMicAsk.known(hear: hear) else { return make(lines: ["Can't"]) }
        return make(lines: ["Mic: \(hear)"])
    }

    /// The short line beside the bolt. The first beat says Listen.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Listen" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Listen"
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

    private static func make(lines: [String]) -> TalkMicDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Listen"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return TalkMicDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
