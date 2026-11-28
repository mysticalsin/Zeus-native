import Foundation

/// A spoken weather ask, and the cards drawn while Zeus answers it.
///
/// The voice says the sky and the temperature. The screen builds Weather, then the sky,
/// then the degrees. With no forecast, the second card is Not ready.
public enum WeatherAsk {
    public static let notReady = "Weather isn't ready."

    /// True for a direct weather ask. Opening the Weather app is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["weather"], ["the", "weather"], ["what", "the", "weather"], ["what", "is", "the", "weather"],
             ["whats", "the", "weather"], ["how", "the", "weather"], ["how", "is", "the", "weather"],
             ["hows", "the", "weather"], ["what", "the", "forecast"], ["what", "is", "the", "forecast"],
             ["the", "forecast"], ["weather", "today"], ["what", "the", "weather", "today"],
             ["how", "the", "weather", "today"], ["how", "is", "the", "weather", "today"]:
            return true
        default:
            return false
        }
    }

    /// Nil when the sky line is blank. A missing place stays out of the sentence.
    public static func line(degrees: Int, phrase: String, place: String) -> String? {
        guard let phrase = trimmed(phrase) else { return nil }
        if let place = trimmed(place) { return "\(phrase) in \(place), \(degrees) degrees." }
        return "\(phrase), \(degrees) degrees."
    }

    private static func words(in text: String) -> [String] {
        let folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        let raw = folded.split { !$0.isLetter && $0 != "'" }.map { token -> String in
            var word = String(token)
            if word.hasSuffix("'s"), word.count > 3 { word = String(word.dropLast(2)) }
            return word.replacingOccurrences(of: "'", with: "")
        }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "zeus", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }

    private static func trimmed(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct WeatherDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var phrase: String?
    public var temperature: String?

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, phrase: String?, temperature: String?) {
        self.draw = draw
        self.schedule = schedule
        self.phrase = phrase
        self.temperature = temperature
    }

    /// Nil when the sky line or the temperature is blank.
    public static func plan(phrase: String, temperature: String) -> WeatherDraw? {
        guard let phrase = clean(phrase), let temperature = clean(temperature) else { return nil }
        return make(cards: [phrase, temperature], phrase: phrase, temperature: temperature)
    }

    /// Weather, then Not ready.
    public static func notReady() -> WeatherDraw {
        make(cards: ["Not ready"], phrase: nil, temperature: nil)
    }

    /// The short line beside the bolt. The first beat says Weather.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Weather" }
        if last == 1 { return phrase.map(Self.shortLine) ?? "Not ready" }
        return temperature.map(Self.shortLine) ?? phrase.map(Self.shortLine) ?? "Weather"
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

    private static func make(cards: [String], phrase: String?, temperature: String?) -> WeatherDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Weather"), at: 0),
        ]
        for (index, text) in cards.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return WeatherDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), phrase: phrase, temperature: temperature)
    }

    private static func clean(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(TalkDraw.maxTextCharacters))
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
