import Foundation

/// A spoken explanation plus the marks the existing talk drawing surface already shows.
///
/// `TalkVisualPresenter` takes a `TalkDraw`, then `reveal(sentence:)` shows the marks for that
/// sentence when the line starts. This value is that plan, built on the Mac with no model call,
/// no screenshot, and no provider key. The canonical canvas is 1280 by 720 screenshot pixels,
/// top-left origin, the same space as `[DRAW]`. `scaled(toWidth:toHeight:)` fits the display
/// the presenter is about to use.
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

    /// An explain request becomes words and a drawing plan. A command, or "explain" with no
    /// subject, stays nil so the rest of the turn can decide. The words quote the question.
    /// They do not assert that the subject happens.
    public static func plan(for request: String) -> ExplainShowcase? {
        guard let subject = subject(in: request) else { return nil }
        let label = String(subject.prefix(TalkDraw.maxTextCharacters))
        let sentences = [
            "I'll draw this as an illustration.",
            "The ring marks the question and the arrow points at it.",
            "You asked: \(label). This sketch is not a sourced claim.",
        ]
        let marks = [
            TalkDraw.Mark(shape: .card(origin: .init(x: 96, y: 72), text: "Illustration"), at: 0),
            TalkDraw.Mark(shape: .ring(center: .init(x: 640, y: 360), radius: 28), at: 1),
            TalkDraw.Mark(shape: .arrow(from: .init(x: 220, y: 520), to: .init(x: 600, y: 380)), at: 1),
            TalkDraw.Mark(shape: .card(origin: .init(x: 96, y: 150), text: label), at: 2),
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
