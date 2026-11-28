import Foundation

/// A spoken dictation check, and the cards drawn while Zeus answers it.
///
/// The voice says whether dictation is ready, listening, transcribing, or polishing.
/// The words being heard stay off the card. The output stays on its own card.
public enum DictationLiveAsk {
    public static let unread = "I can't read dictation."
    public static let phases = ["Ready", "Listening", "Transcribing", "Polishing", "Failed"]

    /// True for a direct ask about dictation. Today's word count is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["is", "dictation", "on"], ["is", "dictation", "listening"],
             ["are", "you", "dictating"], ["how", "is", "dictation"],
             ["how", "is", "my", "dictation"], ["dictation", "status"], ["dictation"]:
            return true
        default:
            return false
        }
    }

    /// The mode name that fits on the card. Blank is nil.
    public static func cardName(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        return String(flat.prefix(TalkDraw.maxTextCharacters))
    }

    /// Unread when the phase is missing. A failure does not repeat its message.
    public static func line(seen: Bool, phase: String, mode: String) -> String {
        guard seen, phases.contains(phase) else { return unread }
        let mode = cardName(mode)
        switch phase {
        case "Ready": return "Dictation is ready."
        case "Listening":
            guard let mode else { return "Dictation is listening." }
            return "Dictation is listening in \(mode)."
        case "Transcribing": return "Dictation is transcribing on your Mac."
        case "Polishing":
            guard let mode else { return "Dictation is polishing." }
            return "Dictation is polishing with \(mode)."
        case "Failed": return "Dictation didn't finish."
        default: return unread
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

public struct DictationLiveDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// Unread draws Can't. Listening and polishing add the mode. A failure is only Failed.
    public static func plan(seen: Bool, phase: String, mode: String) -> DictationLiveDraw {
        guard seen, DictationLiveAsk.phases.contains(phase) else { return make(lines: ["Can't"], name: "") }
        let mode = DictationLiveAsk.cardName(mode)
        let lines: [String]
        switch phase {
        case "Listening", "Polishing":
            lines = mode.map { [phase, $0] } ?? [phase]
        default:
            lines = [phase]
        }
        return make(lines: lines, name: mode ?? "")
    }

    /// The short line beside the bolt. The first beat says Dictation.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Dictation" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Dictation"
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

    private static func make(lines: [String], name: String) -> DictationLiveDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Dictation"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return DictationLiveDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
