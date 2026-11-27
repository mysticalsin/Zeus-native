import Foundation

/// A spoken explanation plus the marks the existing talk drawing surface already shows.
///
/// Beats are revealed in order, one `ExplainBeatSchedule.gap` apart, including when no voice
/// engine starts. A motion ask (fly, move, path, and the words listed below) draws an open pen
/// stroke that grows across those beats. The words name the mechanism and say the drawing does
/// not prove the asked end happens. Canvas is 1280 by 720 screenshot pixels, top-left origin.
/// No model call, no screenshot, and no provider key.
public struct ExplainShowcase: Equatable, Sendable {
    public static let canvasWidth = 1280.0
    public static let canvasHeight = 720.0

    public var sentences: [String]
    public var draw: TalkDraw
    /// True when the mechanism beat is an open traveling stroke rather than a closed box.
    public var travels: Bool
    public var schedule: ExplainBeatSchedule
    /// Open stroke in canvas pixels. Empty when the ask is not about motion. The pen shows a
    /// prefix of this, one new point at a time.
    public var stroke: [TalkDraw.Point]

    public init(sentences: [String], draw: TalkDraw, travels: Bool, schedule: ExplainBeatSchedule,
                stroke: [TalkDraw.Point] = []) {
        self.sentences = sentences
        self.draw = draw
        self.travels = travels
        self.schedule = schedule
        self.stroke = stroke
    }

    public var explanation: String { sentences.joined(separator: " ") }

    /// Nil for a command, or for "explain" with no subject.
    public static func plan(for request: String) -> ExplainShowcase? {
        guard let subject = subject(in: request) else { return nil }
        let pieces = parts(of: subject)
        let start = clip(pieces.start)
        let asked = clip(pieces.asked)
        guard !start.isEmpty, !asked.isEmpty else { return nil }
        let motion = asksMotion(subject)
        let sentences = motion ? motionSentences(start: start, asked: asked) : stillSentences(start: start)
        let stroke = motion ? motionStroke : []
        let marks = motion ? motionMarks(asked: asked, stroke: stroke) : stillMarks(start: start, asked: asked)
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ExplainShowcase(sentences: sentences, draw: draw, travels: motion,
                               schedule: ExplainBeatSchedule(indexes: indexes), stroke: stroke)
    }

    /// The short line beside the bolt for the sentence that is visible at `elapsed`.
    /// A negative or non-finite time stays on the first sentence. The line is at most 40 characters.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let beat: Int
        if travels {
            beat = penFrame(at: elapsed)?.beat ?? 0
        } else {
            beat = max(schedule.revealed(at: elapsed).count - 1, 0)
        }
        guard !sentences.isEmpty else { return "Here" }
        let index = min(max(beat, 0), sentences.count - 1)
        return Self.shortLine(sentences[index])
    }

    /// Where the bolt sits at `elapsed`. A moving ask follows the pen tip. A still ask
    /// sits on the newest mark: a ring, then an arrow, then the ink, then a card.
    public func guideBolt(at elapsed: TimeInterval) -> TalkDraw.Point? {
        if travels {
            guard let bolt = penFrame(at: elapsed)?.bolt, Self.finite(bolt) else { return nil }
            return bolt
        }
        let shown = Set(schedule.revealed(at: elapsed))
        let marks = draw.marks.filter { shown.contains($0.at) }
        guard let beat = marks.map(\.at).max() else { return nil }
        let atBeat = marks.filter { $0.at == beat }
        let placed = atBeat.compactMap { mark -> (Int, TalkDraw.Point)? in
            guard let point = Self.anchor(of: mark) else { return nil }
            return (Self.preference(mark), point)
        }
        return placed.min { $0.0 < $1.0 }?.1
    }

    /// A ring is the place to land. An arrow, the ink, then a card follow.
    private static func preference(_ mark: TalkDraw.Mark) -> Int {
        switch mark.shape {
        case .ring: return 0
        case .arrow: return 1
        case .ink: return 2
        case .card: return 3
        }
    }

    private static func finite(_ point: TalkDraw.Point) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private static func anchor(of mark: TalkDraw.Mark) -> TalkDraw.Point? {
        let point: TalkDraw.Point
        switch mark.shape {
        case .ring(let center, let radius):
            guard radius.isFinite, radius > 0 else { return nil }
            point = center
        case .arrow(let from, let to):
            point = .init(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        case .ink(let points):
            guard let last = points.last else { return nil }
            point = last
        case .card(let origin, _):
            point = origin
        }
        guard finite(point) else { return nil }
        return point
    }

    /// The ink visible at `elapsed`. Without audio, one new point every `ExplainBeatSchedule.gap`.
    /// With sentence start times, points stay inside the sentence that is actually playing.
    public func penFrame(at elapsed: TimeInterval, audioStarts: [TimeInterval?] = []) -> ExplainPenFrame? {
        guard travels, stroke.count >= 2 else { return nil }
        let steps = stroke.count - 1
        let due = (0..<steps).filter { stepTime($0, steps: steps, audioStarts: audioStarts) <= max(0, elapsed) }
        let step = due.max() ?? 0
        let count = min(stroke.count, step + 2)
        let shown = Array(stroke.prefix(count))
        let beat = min(2, step * 3 / steps)
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ink(shown), at: 0),
            .init(shape: .ring(center: shown[shown.count - 1], radius: 18), at: 0),
            .init(shape: .card(origin: .init(x: 200, y: 140), text: "force"), at: 0),
        ]
        if beat >= 2 {
            marks.append(.init(shape: .card(origin: .init(x: 200, y: 80), text: "fly?"), at: 2))
        }
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        return ExplainPenFrame(draw: draw, bolt: shown[shown.count - 1], pointCount: count, beat: beat,
                               finished: count == stroke.count)
    }

    private func stepTime(_ step: Int, steps: Int, audioStarts: [TimeInterval?]) -> TimeInterval {
        let beat = min(2, step * 3 / steps)
        let inBeat = (0..<steps).filter { min(2, $0 * 3 / steps) == beat }
        let local = inBeat.firstIndex(of: step) ?? 0
        if audioStarts.contains(where: { $0 != nil }), beat < audioStarts.count, let start = audioStarts[beat] {
            let next = beat + 1 < audioStarts.count ? audioStarts[beat + 1] : nil
            let window = next.map { max($0 - start, 0.05) } ?? ExplainBeatSchedule.gap * Double(max(inBeat.count, 1))
            return start + window * Double(local) / Double(max(inBeat.count, 1))
        }
        return Double(step) * ExplainBeatSchedule.gap
    }

    /// True while the words are an explain request, including before the subject is long enough
    /// to draw. The speculative model race stays quiet for these, so the local plan is the answer.
    public static func blocksModelRace(_ request: String) -> Bool {
        if plan(for: request) != nil { return true }
        let key = normalized(request)
        return key == "explain" || key.hasPrefix("explain ") || key.contains(" explain ")
            || key.hasPrefix("show me how") || key.hasPrefix("walk me through")
    }

    /// The same marks in the pixel size of one real display. The presenter matches `displayFrame`
    /// to that display; these pixels are the shot size for that frame.
    public func scaled(toWidth width: Int, toHeight height: Int) -> TalkDraw {
        Self.scaled(draw, toWidth: width, toHeight: height)
    }

    public static func scaled(_ draw: TalkDraw, toWidth width: Int, toHeight height: Int) -> TalkDraw {
        let sx = Double(max(width, 1)) / canvasWidth
        let sy = Double(max(height, 1)) / canvasHeight
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

    /// Pixel size of a display frame at `scale` backing, the same numbers the talk presenter uses.
    /// A non-finite edge is one pixel, except positive infinity, which is the largest 32-bit pixel count.
    public static func pixelSize(width: Double, height: Double, scale: Double) -> (width: Int, height: Int) {
        let factor = scale.isFinite ? max(scale, 1) : 1
        func axis(_ value: Double) -> Int {
            guard value.isFinite else { return value > 0 ? Int(Int32.max) : 1 }
            let scaled = (value * factor).rounded()
            guard scaled.isFinite else { return scaled > 0 ? Int(Int32.max) : 1 }
            if scaled >= Double(Int32.max) { return Int(Int32.max) }
            return max(1, Int(scaled))
        }
        return (axis(width), axis(height))
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

    private static let motionWords: Set<String> = [
        "fly", "flying", "flight", "move", "moving", "motion", "path", "travel", "traveling",
        "rise", "rising", "lift", "drive", "roll", "spin", "jump", "fall", "swim", "run",
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

    private static func asksMotion(_ subject: String) -> Bool {
        !Set(subject.split(separator: " ").map(String.init)).isDisjoint(with: motionWords)
    }

    /// "the tesla car can fly" -> start "tesla car", asked "fly".
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

    /// One caption line, matching the bolt's 40-character limit.
    private static func shortLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > 40 { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? "Here" : line
    }

    private static func leading(_ label: String) -> String {
        guard let first = label.first else { return label }
        return first.uppercased() + label.dropFirst()
    }

    /// The mechanism is an upward force the sketch does not contain. No registry source is invented.
    /// The last sentence still refuses to treat the drawing as proof.
    private static func motionSentences(start: String, asked: String) -> [String] {
        [
            "To leave the ground, \(start) would need an upward force greater than its weight, from a wing or a rotor this sketch does not draw.",
            "No source is on file for that force. The pen only traces the question.",
            "The asked end is \(asked). The drawing does not prove that the end happens.",
        ]
    }

    private static func stillSentences(start: String) -> [String] {
        [
            "\(leading(start)) is the start of the explanation.",
            "The next mark is the change you asked to see.",
            "The drawing does not prove that the end happens.",
        ]
    }

    /// One open stroke. The live pen shows a prefix, one new point at a time. Not a closed box.
    private static let motionStroke: [TalkDraw.Point] = [
        .init(x: 200, y: 500), .init(x: 480, y: 500), .init(x: 640, y: 440),
        .init(x: 760, y: 360), .init(x: 900, y: 280), .init(x: 1040, y: 200),
    ]

    private static func motionMarks(asked: String, stroke: [TalkDraw.Point]) -> [TalkDraw.Mark] {
        let tip = stroke.last ?? .init(x: 200, y: 500)
        return [
            .init(shape: .ink(stroke), at: 0),
            .init(shape: .ring(center: tip, radius: 18), at: 0),
            .init(shape: .card(origin: .init(x: 200, y: 140), text: "force"), at: 0),
            .init(shape: .card(origin: .init(x: 200, y: 80), text: askedCard(asked)), at: 2),
        ]
    }

    private static func stillMarks(start: String, asked: String) -> [TalkDraw.Mark] {
        let box = [
            TalkDraw.Point(x: 180, y: 220), TalkDraw.Point(x: 460, y: 220),
            TalkDraw.Point(x: 460, y: 420), TalkDraw.Point(x: 180, y: 420),
            TalkDraw.Point(x: 180, y: 220),
        ]
        return [
            .init(shape: .ink(box), at: 0),
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: start), at: 0),
            .init(shape: .arrow(from: .init(x: 480, y: 320), to: .init(x: 900, y: 320)), at: 1),
            .init(shape: .card(origin: .init(x: 920, y: 280), text: askedCard(asked)), at: 2),
        ]
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

/// One moment of the pen: the ink drawn so far and where the bolt sits.
public struct ExplainPenFrame: Equatable, Sendable {
    public var draw: TalkDraw
    public var bolt: TalkDraw.Point
    public var pointCount: Int
    public var beat: Int
    public var finished: Bool

    public init(draw: TalkDraw, bolt: TalkDraw.Point, pointCount: Int, beat: Int, finished: Bool) {
        self.draw = draw
        self.bolt = bolt
        self.pointCount = pointCount
        self.beat = beat
        self.finished = finished
    }
}

/// When each explain beat becomes visible. Time zero shows only the first beat.
public struct ExplainBeatSchedule: Equatable, Sendable {
    public static let gap: TimeInterval = 0.7

    public var indexes: [Int]

    public init(indexes: [Int]) {
        let unique = Array(Set(indexes)).sorted()
        self.indexes = unique.isEmpty ? [0] : unique
    }

    /// Beats whose start time is at or before `elapsed`. Later beats stay hidden.
    /// A negative or non-finite time stays on the first beat.
    public func revealed(at elapsed: TimeInterval) -> [Int] {
        guard elapsed.isFinite, elapsed > 0 else {
            return Array(indexes.prefix(1))
        }
        let raw = elapsed / Self.gap
        if !raw.isFinite || raw >= Double(indexes.count) {
            return indexes
        }
        let steps = Int(raw.rounded(.down))
        let count = min(indexes.count, steps + 1)
        return Array(indexes.prefix(max(count, 1)))
    }
}
