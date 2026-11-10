import Foundation

/// One spoken word with times from a silent render. Seconds, from the start of the utterance.
public struct SpeechWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct TimelineCue: Equatable, Sendable {
    public var index: Int
    public var start: Double
    public var end: Double

    public init(index: Int, start: Double, end: Double) {
        self.index = index
        self.start = start
        self.end = end
    }
}

/// Drawing steps locked to word times. A click, a key, or a new utterance cancels what is left.
public struct SpeechDrawingTimeline: Equatable, Sendable {
    public private(set) var cues: [TimelineCue]
    public private(set) var cancelled = false
    public private(set) var cancelReason: String?
    /// Set when a real word list replaces an estimate. The estimate is not used after that.
    public private(set) var usedEstimate = false

    public init(cues: [TimelineCue], usedEstimate: Bool = false) {
        self.cues = cues
        self.usedEstimate = usedEstimate
    }

    /// Splits the words into `stepCount` contiguous groups. Steps do not share a start time.
    public static func schedule(words: [SpeechWord], stepCount: Int) -> SpeechDrawingTimeline {
        let count = min(max(stepCount, 0), words.count)
        guard count > 0 else { return SpeechDrawingTimeline(cues: []) }
        var cues: [TimelineCue] = []
        var cursor = 0
        for index in 0..<count {
            let remaining = words.count - cursor
            let slots = count - index
            let take = max(1, remaining / slots)
            let group = words[cursor..<(cursor + take)]
            cursor += take
            let start = group.first!.start
            let previousEnd = cues.last?.end
            let adjusted = previousEnd.map { max(start, $0) } ?? start
            cues.append(TimelineCue(index: index, start: adjusted, end: group.last!.end))
        }
        return SpeechDrawingTimeline(cues: cues, usedEstimate: false)
    }

    /// Even slices of the text when no word times exist yet. 0.18 s per word.
    public static func estimate(text: String, stepCount: Int) -> SpeechDrawingTimeline {
        let words = text.split(whereSeparator: \.isWhitespace).enumerated().map { index, word in
            let start = Double(index) * 0.18
            return SpeechWord(text: String(word), start: start, end: start + 0.18)
        }
        var timeline = schedule(words: words, stepCount: stepCount)
        timeline.usedEstimate = true
        return timeline
    }

    /// Real times replace the estimate. Nothing from the estimate remains.
    public func committed(words: [SpeechWord], stepCount: Int) -> SpeechDrawingTimeline {
        // A late TTS alignment result must not restart ink after the user stopped the turn.
        guard !cancelled else { return self }
        return Self.schedule(words: words, stepCount: stepCount)
    }

    /// The step that should be on screen at `time`. Nil before the first word, after cancel, or when empty.
    public func step(at time: Double) -> Int? {
        guard !cancelled else { return nil }
        var current: Int?
        for cue in cues where cue.start <= time {
            current = cue.index
        }
        return current
    }

    public mutating func interrupt(reason: String) {
        cancelled = true
        cancelReason = reason
    }
}

/// Text the dictate-file hook can hand to the timeline without playing audio.
public enum PresentTimeline {
    public static func report(text: String, stepCount: Int = 3) -> String {
        let timeline = SpeechDrawingTimeline.estimate(text: text, stepCount: stepCount)
        let math = MathTypeset.render("a^2+b^2=c^2")
        var lines = [
            "source=text",
            "estimate=\(timeline.usedEstimate)",
            "cancelled=\(timeline.cancelled)",
            "math=\(math.spoken)",
            "mathHasDollar=\(math.spoken.contains("$"))",
        ]
        for cue in timeline.cues {
            lines.append("step\(cue.index).start=\(String(format: "%.3f", cue.start))")
            lines.append("step\(cue.index).end=\(String(format: "%.3f", cue.end))")
        }
        return lines.joined(separator: "\n")
    }
}
