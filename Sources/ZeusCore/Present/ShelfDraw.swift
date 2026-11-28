import Foundation

/// A spoken shelf ask, and the cards drawn while Zeus answers it.
///
/// The voice says what is sitting there. One file builds Shelf, then the name, then 1 file.
/// Several build Shelf, then the count, then the newest name. The file search stays on its own card.
public enum ShelfAsk {
    public static let empty = "The shelf is empty."

    /// True for a direct ask about the shelf. Finding a file is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["shelf"], ["my", "shelf"], ["the", "shelf"],
             ["what", "is", "on", "my", "shelf"], ["what", "is", "on", "the", "shelf"],
             ["what", "is", "on", "the", "file", "shelf"],
             ["how", "many", "files", "on", "my", "shelf"], ["how", "many", "files", "on", "the", "shelf"],
             ["how", "many", "files", "are", "on", "my", "shelf"],
             ["how", "many", "files", "are", "on", "the", "shelf"]:
            return true
        default:
            return false
        }
    }

    /// Nil when the count is below one. A blank name leaves the newest file out of the sentence.
    public static func line(count: Int, name: String) -> String? {
        guard count >= 1 else { return nil }
        let name = cardName(name, limit: 200)
        if count == 1 {
            guard let name else { return "You have 1 file on the shelf." }
            return "You have \(name) on the shelf."
        }
        guard let name else { return "You have \(count) files on the shelf." }
        return "You have \(count) files on the shelf. The newest is \(name)."
    }

    /// A card name, cut on a word once it passes 60 characters.
    public static func cardName(_ raw: String, limit: Int = 60) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        if flat.count <= limit { return flat }
        let cut = String(flat.prefix(limit))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > 12 {
            return String(cut[..<space])
        }
        return cut
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

public struct ShelfDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var count: String
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, count: String, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.count = count
        self.name = name
    }

    /// Nil when the count is below one.
    public static func plan(count: Int, name: String) -> ShelfDraw? {
        guard ShelfAsk.line(count: count, name: name) != nil else { return nil }
        let shown = ShelfAsk.cardName(name) ?? ""
        if count == 1 {
            let lines = shown.isEmpty ? ["1 file"] : [shown, "1 file"]
            return make(lines: lines, count: lines.count > 1 ? "1 file" : "1 file", name: shown)
        }
        let left = "\(count) files"
        let lines = shown.isEmpty ? [left] : [left, shown]
        return make(lines: lines, count: left, name: shown)
    }

    public static func empty() -> ShelfDraw { make(lines: ["None"], count: "", name: "") }

    /// The short line beside the bolt. The first beat says Shelf.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Shelf" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Shelf"
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

    private static func make(lines: [String], count: String, name: String) -> ShelfDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Shelf"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ShelfDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), count: count, name: name)
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
