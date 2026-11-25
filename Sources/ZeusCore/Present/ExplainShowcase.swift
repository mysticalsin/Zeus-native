import Foundation

/// A spoken explanation plus the marks the existing talk drawing surface already shows.
///
/// An explain request is demonstrated in three beats. Beat 0 draws a closed figure and rings it.
/// Beat 1 draws the arrow that leaves that figure. Beat 2 names the asked end. `TalkVisualPresenter`
/// reveals the marks for a beat when that sentence starts. The canvas is 1280 by 720 screenshot
/// pixels, top-left origin, the same space as `[DRAW]`. No model call, no screenshot, and no provider key.
public struct ExplainShowcase: Equatable, Sendable {
    public static let canvasWidth = 1280.0
    public static let canvasHeight = 720.0

    public var sentences: [String]
    public var draw: TalkDraw

    public init(sentences: [String], draw: TalkDraw) {
        self.sentences = sentences
        self.draw = draw
    }

    public var explanation: String { sentences.joined(separator: " ") }

    /// Nil for a command, or for "explain" with no subject. The words name the start and the asked
    /// end. They do not assert that the asked end happens.
    public static func plan(for request: String) -> ExplainShowcase? {
        guard let subject = subject(in: request) else { return nil }
        let pieces = parts(of: subject)
        let start = clip(pieces.start)
        let asked = clip(pieces.asked)
        guard !start.isEmpty, !asked.isEmpty else { return nil }
        let sentences = [
            "\(leading(start)) is the start, drawn as a closed box and ringed.",
            "The arrow leaves that box. It is the change you asked about.",
            endSentence(asked),
        ]
        let box = [
            TalkDraw.Point(x: 180, y: 220),
            TalkDraw.Point(x: 460, y: 220),
            TalkDraw.Point(x: 460, y: 420),
            TalkDraw.Point(x: 180, y: 420),
            TalkDraw.Point(x: 180, y: 220),
        ]
        let marks = [
            TalkDraw.Mark(shape: .ink(box), at: 0),
            TalkDraw.Mark(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            TalkDraw.Mark(shape: .card(origin: .init(x: 180, y: 160), text: start), at: 0),
            TalkDraw.Mark(shape: .arrow(from: .init(x: 480, y: 320), to: .init(x: 900, y: 320)), at: 1),
            TalkDraw.Mark(shape: .card(origin: .init(x: 920, y: 280), text: askedCard(asked)), at: 2),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        return ExplainShowcase(sentences: sentences, draw: draw)
    }

    /// True while the words are an explain request, including before the subject is long enough
    /// to draw. The speculative model race stays quiet for these, so the local plan is the answer.
    public static func blocksModelRace(_ request: String) -> Bool {
        if plan(for: request) != nil { return true }
        let key = normalized(request)
        return key == "explain" || key.hasPrefix("explain ") || key.contains(" explain ")
            || key.hasPrefix("show me how") || key.hasPrefix("walk me through")
    }

    /// The same marks in the pixel size of the shot the presenter is given.
    public func scaled(toWidth width: Int, toHeight height: Int) -> TalkDraw {
        let sx = Double(max(width, 1)) / Self.canvasWidth
        let sy = Double(max(height, 1)) / Self.canvasHeight
        let sr = min(sx, sy)
        func point(_ value: TalkDraw.Point) -> TalkDraw.Point {
            .init(x: value.x * sx, y: value.y * sy)
        }
        let marks: [TalkDraw.Mark] = draw.marks.map { mark in
            switch mark.shape {
            case .ring(let center, let radius):
                return .init(shape: .ring(center: point(center), radius: max(TalkDraw.minRingRadius, radius * sr)), at: mark.at)
            case .arrow(let from, let to):
                return .init(shape: .arrow(from: point(from), to: point(to)), at: mark.at)
            case .ink(let points):
                return .init(shape: .ink(points.map(point)), at: mark.at)
            case .card(let origin, let text):
                return .init(shape: .card(origin: point(origin), text: text), at: mark.at)
            }
        }
        return TalkDrawParser.parse(TalkDraw(screen: draw.screen, marks: marks).json) ?? TalkDraw(screen: draw.screen, marks: marks)
    }

    private static let leads = [
        "can you explain how ",
        "could you explain how ",
        "please explain how ",
        "explain to me how ",
        "explain how ",
        "explain why ",
        "explain what ",
        "show me how ",
        "walk me through ",
        "can you explain ",
        "please explain ",
        "explain ",
    ]

    private static func subject(in request: String) -> String? {
        let key = normalized(request)
        for lead in leads where key.hasPrefix(lead) {
            let subject = String(key.dropFirst(lead.count))
            let words = subject.split(separator: " ")
            guard words.count >= 2, subject.count <= 240 else { return nil }
            return subject
        }
        return nil
    }

    /// "the tesla car can fly" -> start "tesla car", asked "fly". With no change word, the asked end stays "question".
    private static func parts(of subject: String) -> (start: String, asked: String) {
        for separator in [" can ", " could ", " to ", " will "] {
            guard let range = subject.range(of: separator) else { continue }
            let start = bare(String(subject[..<range.lowerBound]))
            let asked = bare(String(subject[range.upperBound...]))
            if !start.isEmpty, !asked.isEmpty { return (start, asked) }
        }
        let start = bare(subject)
        return (start.isEmpty ? subject : start, "question")
    }

    private static func bare(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        while let first = words.first, ["the", "a", "an"].contains(first) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    private static func clip(_ text: String) -> String {
        String(text.prefix(TalkDraw.maxTextCharacters))
    }

    private static func askedCard(_ asked: String) -> String {
        if asked == "question" { return "question" }
        let marked = asked.hasSuffix("?") ? asked : asked + "?"
        return String(marked.prefix(TalkDraw.maxTextCharacters))
    }

    private static func leading(_ label: String) -> String {
        guard let first = label.first else { return label }
        return first.uppercased() + label.dropFirst()
    }

    private static func endSentence(_ asked: String) -> String {
        if asked == "question" {
            return "The arrow's far end is still only a question. The drawing does not show that it happens."
        }
        return "The asked end is \(asked). The drawing does not show that it happens."
    }

    private static func normalized(_ request: String) -> String {
        let folded = request.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        let spaced = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(spaced).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
