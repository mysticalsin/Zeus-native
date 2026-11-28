import Foundation

/// The pinned Home note, drawn while Zeus reads it.
///
/// The voice says the note. The screen builds Note, then the words.
/// A blank note shows None. A password is not read and shows Not stored.
public enum NoteAsk {
    public static let none = "There's no note."
    public static let secret = "I can't read that."

    /// True for a direct ask to read the pinned note. A reminder and a memory are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["note"], ["my", "note"], ["the", "note"], ["pinned", "note"],
             ["read", "note"], ["read", "my", "note"], ["read", "the", "note"],
             ["read", "my", "pinned", "note"],
             ["what", "is", "my", "note"], ["what", "my", "note"]:
            return true
        default:
            return false
        }
    }

    /// True when the note must not be spoken or shown.
    public static func refuses(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("password") || lower.contains("cvv") || lower.contains("social security")
    }

    /// The note as a spoken sentence. Nil when it is blank or must not be read.
    public static func line(_ text: String) -> String? {
        guard let spoken = wordsOf(text), !refuses(spoken) else { return nil }
        if let last = spoken.last, ".!?".contains(last) { return spoken }
        return spoken + "."
    }

    /// The card line, at most 60 characters, cut on a word. Nil when the note must not be shown.
    static func cardText(_ text: String) -> String? {
        guard let spoken = wordsOf(text), !refuses(spoken) else { return nil }
        if spoken.count <= TalkDraw.maxTextCharacters { return spoken }
        var current = ""
        for word in spoken.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > TalkDraw.maxTextCharacters { break }
            current = next
        }
        return current.isEmpty ? String(spoken.prefix(TalkDraw.maxTextCharacters)) : current
    }

    private static func wordsOf(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { token -> String in
            var word = String(token)
            if word.hasSuffix("'s"), word.count > 3 { word = String(word.dropLast(2)) }
            return word.replacingOccurrences(of: "'", with: "")
        }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct NoteDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var note: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, note: String) {
        self.draw = draw
        self.schedule = schedule
        self.note = note
    }

    /// Nil when the note is blank or must not be shown.
    public static func plan(text: String) -> NoteDraw? {
        guard let note = NoteAsk.cardText(text) else { return nil }
        return make(lines: [note], note: note)
    }

    public static func none() -> NoteDraw {
        make(lines: ["None"], note: "")
    }

    public static func secret() -> NoteDraw {
        make(lines: ["Not stored"], note: "")
    }

    /// The short line beside the bolt. The first beat says Note.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Note" }
        return note.isEmpty ? (linesContainNone ? "None" : "Not stored") : Self.shortLine(note)
    }

    private var linesContainNone: Bool {
        draw.marks.contains { mark in
            if case .card(_, let text) = mark.shape { return text == "None" }
            return false
        }
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

    private static func make(lines: [String], note: String) -> NoteDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Note"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return NoteDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), note: note)
    }

    private static func shortLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > 40 { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? String(raw.prefix(40)) : line
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
