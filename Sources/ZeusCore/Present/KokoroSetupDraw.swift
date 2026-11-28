import Foundation

/// A spoken check of Kokoro on this Mac, and the cards drawn while Zeus answers it.
///
/// Whether the model files are present, and which of the nine voices is chosen.
/// Which engine speaks, and the pace, stay their own asks. Nothing is downloaded or played.
public enum KokoroSetupAsk {
    public static let unread = "I can't read how Kokoro is set."
    public static let ready = ["Ready", "Not set up"]
    /// The same titles as the Kokoro voice menu.
    public static let voices = [
        "Michael (US)", "Adam (US)", "Eric (US)",
        "George (UK)", "Lewis (UK)", "Daniel (UK)",
        "Emma (UK)", "Heart (US)", "Bella (US)",
    ]

    /// True for a direct ask about Kokoro. Which engine speaks is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "kokoro", "voice"], ["how", "is", "kokoro", "set"],
             ["is", "kokoro", "ready"], ["kokoro", "voice", "settings"],
             ["is", "kokoro", "set", "up"], ["which", "kokoro", "voice", "is", "chosen"]:
            return true
        default:
            return false
        }
    }

    /// A known setup and a known voice use that sentence. Anything else is unread.
    public static func line(setup: String, voice: String) -> String {
        guard known(setup: setup, voice: voice) else { return unread }
        let state = setup == "Ready" ? "Kokoro is ready" : "Kokoro is not set up"
        return "\(state), and the voice is \(voice)."
    }

    public static func known(setup: String, voice: String) -> Bool {
        ready.contains(setup) && voices.contains(voice)
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

public struct KokoroSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Kokoro, then the setup and the voice.
    public static func plan(setup: String, voice: String) -> KokoroSetupDraw {
        guard KokoroSetupAsk.known(setup: setup, voice: voice) else { return make(lines: ["Can't"]) }
        return make(lines: ["Setup: \(setup)", "Voice: \(voice)"])
    }

    /// The short line beside the bolt. The first beat says Kokoro.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Kokoro" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Kokoro"
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

    private static func make(lines: [String]) -> KokoroSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Kokoro"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return KokoroSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
