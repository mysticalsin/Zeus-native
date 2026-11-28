import Foundation

/// A spoken check of the Polyglot shortcut and the engine that hears, and the cards drawn while Zeus answers it.
///
/// The key is off, the default, or one you chose. The engine is chosen at start, Parakeet, or Apple.
/// Whether Polyglot is on, and the captions, stay their own asks. The chord is not spoken, and nothing is started.
public enum PolyglotChordAsk {
    public static let unread = "I can't read the Polyglot key."
    public static let keys = ["Off", "Default", "Chosen"]
    public static let engines = ["Start", "Parakeet", "Apple"]

    /// True for a direct ask about the shortcut or the engine. Live translation is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["what", "is", "the", "polyglot", "key"], ["how", "is", "the", "polyglot", "shortcut", "set"],
             ["which", "polyglot", "engine"], ["polyglot", "shortcut", "settings"],
             ["is", "the", "polyglot", "key", "off"], ["which", "engine", "hears", "polyglot"]:
            return true
        default:
            return false
        }
    }

    /// Two known choices use that sentence. Anything else is unread.
    public static func line(key: String, engine: String) -> String {
        guard known(key: key, engine: engine) else { return unread }
        return "The Polyglot key is \(keyWord(key)), and the engine is \(engineWord(engine))."
    }

    public static func known(key: String, engine: String) -> Bool {
        keys.contains(key) && engines.contains(engine)
    }

    private static func keyWord(_ key: String) -> String {
        switch key {
        case "Off": "off"
        case "Chosen": "one you chose"
        default: "the default"
        }
    }

    private static func engineWord(_ engine: String) -> String {
        switch engine {
        case "Parakeet": "Parakeet"
        case "Apple": "Apple"
        default: "chosen at start"
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

public struct PolyglotChordDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Chord, then the key and the engine.
    public static func plan(key: String, engine: String) -> PolyglotChordDraw {
        guard PolyglotChordAsk.known(key: key, engine: engine) else { return make(lines: ["Can't"]) }
        return make(lines: ["Key: \(key)", "Hear: \(engine)"])
    }

    /// The short line beside the bolt. The first beat says Chord.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Chord" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Chord"
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

    private static func make(lines: [String]) -> PolyglotChordDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Chord"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PolyglotChordDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
