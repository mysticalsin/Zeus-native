import Foundation

/// A spoken check of the chat model, and the cards drawn while Zeus answers it.
///
/// The model the menu shows, and whether that provider has a saved key.
/// Who answers stays its own ask. The key stays off the card. Nothing is saved.
public enum ChatModelAsk {
    public static let unread = "I can't read the chat model."
    /// Every title the Model menu can show.
    public static let models = ["Claude Code default", "gpt-5-mini", "gpt-4.1-mini", "claude-haiku-4-5", "claude-sonnet-4-5"]
    public static let keys = ["Built-in", "Saved", "None"]

    /// True for a direct ask about the chat model. Who answers is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "chat", "model"], ["how", "is", "the", "chat", "model", "set"],
             ["chat", "model", "settings"], ["what", "chat", "model", "is", "selected"],
             ["does", "the", "chat", "model", "need", "a", "key"], ["is", "a", "chat", "model", "key", "saved"]:
            return true
        default:
            return false
        }
    }

    /// A known model and a known key use that sentence. Anything else is unread.
    public static func line(model: String, key: String) -> String {
        guard known(model: model, key: key) else { return unread }
        return "The chat model is \(model), and \(keyLine(key))."
    }

    public static func known(model: String, key: String) -> Bool {
        models.contains(model) && keys.contains(key)
    }

    private static func keyLine(_ key: String) -> String {
        switch key {
        case "Saved": "a key is saved"
        case "None": "no key is saved"
        default: "it needs no key"
        }
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

public struct ChatModelDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Reply, then the model and the key.
    public static func plan(model: String, key: String) -> ChatModelDraw {
        guard ChatModelAsk.known(model: model, key: key) else { return make(lines: ["Can't"]) }
        return make(lines: ["Model: \(model)", "Key: \(key)"])
    }

    /// The short line beside the bolt. The first beat says Reply.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Reply" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Reply"
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

    private static func make(lines: [String]) -> ChatModelDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Reply"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ChatModelDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
