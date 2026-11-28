import Foundation

/// A spoken clipboard count, and the cards drawn while Zeus answers it.
///
/// The voice says how many clips there are and what kind the newest one is.
/// The words on the clipboard stay off the card. The shelf stays on its own card.
public enum ClipboardCountAsk {
    public static let empty = "The clipboard is empty."

    /// True for a direct ask about how many clips are kept. Reading one aloud is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["clipboard"], ["my", "clipboard"], ["the", "clipboard"],
             ["what", "is", "on", "my", "clipboard"], ["what", "is", "on", "the", "clipboard"],
             ["how", "many", "clips"], ["how", "many", "clips", "do", "i", "have"],
             ["how", "many", "clipboard", "items"], ["how", "many", "things", "on", "my", "clipboard"],
             ["how", "many", "things", "on", "the", "clipboard"]:
            return true
        default:
            return false
        }
    }

    /// "Text", "Link", "Image", or "File". Anything else is left off the card.
    public static func kindWord(_ kind: String) -> String? {
        switch kind.lowercased() {
        case "text": "Text"
        case "link": "Link"
        case "image": "Image"
        case "file": "File"
        default: nil
        }
    }

    /// Nil when the count is below one. A blank kind leaves the newest clip's kind out.
    public static func line(count: Int, kind: String) -> String? {
        guard count >= 1 else { return nil }
        let kind = kindWord(kind)?.lowercased()
        if count == 1 {
            guard let kind else { return "You have 1 clip." }
            return "You have 1 \(kind) clip."
        }
        guard let kind else { return "You have \(count) clips." }
        return "You have \(count) clips. The newest is \(kind)."
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
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

public struct ClipboardCountDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var count: String
    public var kind: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, count: String, kind: String) {
        self.draw = draw
        self.schedule = schedule
        self.count = count
        self.kind = kind
    }

    /// Nil when the count is below one. The kind word is only Text, Link, Image, or File.
    public static func plan(count: Int, kind: String) -> ClipboardCountDraw? {
        guard ClipboardCountAsk.line(count: count, kind: kind) != nil else { return nil }
        let kind = ClipboardCountAsk.kindWord(kind) ?? ""
        if count == 1 {
            let lines = kind.isEmpty ? ["1 clip"] : [kind, "1 clip"]
            return make(lines: lines, count: "1 clip", kind: kind)
        }
        let left = "\(count) clips"
        let lines = kind.isEmpty ? [left] : [left, kind]
        return make(lines: lines, count: left, kind: kind)
    }

    public static func empty() -> ClipboardCountDraw { make(lines: ["None"], count: "", kind: "") }

    /// The short line beside the bolt. The first beat says Clips.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Clips" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Clips"
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

    private static func make(lines: [String], count: String, kind: String) -> ClipboardCountDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Clips"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ClipboardCountDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), count: count, kind: kind)
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
