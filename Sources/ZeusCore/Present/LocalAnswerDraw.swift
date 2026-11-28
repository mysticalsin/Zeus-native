import Foundation

/// A local answer drawn on the talk surface while the full sentence is spoken.
///
/// Questions Zeus answers without a model used to be speech only. The card shows one short
/// line of that answer. An empty answer is not drawn.
public struct LocalAnswerDraw: Equatable, Sendable {
    public static let boltLimit = 40

    public var draw: TalkDraw
    public var bolt: String
    public var guide: TalkDraw.Point

    public init(draw: TalkDraw, bolt: String, guide: TalkDraw.Point) {
        self.draw = draw
        self.bolt = bolt
        self.guide = guide
    }

    public static func plan(answer: String) -> LocalAnswerDraw? {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let bolt = shortLine(answer)
        let guide = TalkDraw.Point(x: 320, y: 320)
        let marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: guide, radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: bolt), at: 0),
        ]
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        return LocalAnswerDraw(draw: draw, bolt: bolt, guide: guide)
    }

    /// One card line, at most 40 characters, cut on a word.
    public static func shortLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > boltLimit { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { return line }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Here" : String(trimmed.prefix(boltLimit))
    }
}
