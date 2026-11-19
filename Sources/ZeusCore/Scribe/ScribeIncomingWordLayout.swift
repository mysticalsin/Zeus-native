import Foundation

/// Cached display metadata for an actual transcript batch. This never creates transcript content
/// or decides which words have arrived: the caller supplies its existing visible-word count.
public struct ScribeIncomingWordLayout: Equatable, Sendable {
    public struct Run: Equatable, Sendable {
        /// An exact original substring, including every space, newline and punctuation mark.
        public let text: String
        public let wordIndex: Int?
    }

    public struct Frame: Equatable, Sendable {
        public let opacity: Double
        public let blur: Double
    }

    public let text: String
    public let runs: [Run]
    public let words: [String]
    public let revision: UInt64
    private let starts: [TimeInterval?]
    private let wordRunEnds: [Int]
    private let settlesAt: TimeInterval
    public var revealEndsAt: TimeInterval? { settlesAt.isFinite ? settlesAt : nil }

    /// The 12/sec schedule is the existing ScribeWordReveal presentation rate, not speech timing.
    /// An eligible unchanged word keeps its fade origin when a newer ASR revision arrives.
    /// Corrections to already eligible words replace their text immediately rather than replaying it.
    public init(text: String, alreadyShown: Int, since: TimeInterval,
                previous: Self? = nil, wordsPerSecond: Double = 12) {
        self.text = text
        self.revision = (previous?.revision ?? 0) &+ 1
        let parsed = Self.split(text)
        let words = parsed.words
        self.runs = parsed.runs
        self.words = parsed.words
        self.wordRunEnds = parsed.wordRunEnds
        let shown = min(max(0, alreadyShown), words.count)
        let validClock = since.isFinite && wordsPerSecond.isFinite && wordsPerSecond > 0
        let starts: [TimeInterval?] = words.indices.map { index in
            if index < shown {
                guard let previous, previous.words.indices.contains(index),
                      previous.words[index] == words[index] else { return nil }
                return previous.starts[index]
            }
            guard validClock else { return nil }
            let start = since + Double(index - shown + 1) / wordsPerSecond
            return start.isFinite ? start : nil
        }
        self.starts = starts
        self.settlesAt = starts.compactMap { $0 }.max().map { $0 + RecordingFeedback.Motion.revealDuration } ?? -.infinity
    }

    public func isSettled(at now: TimeInterval, shownWords: Int) -> Bool {
        shownWords >= words.count && (!now.isFinite || now >= settlesAt)
    }

    /// Exact admitted prefix only. Unarrived tail words must not reserve wrapping height and
    /// scroll the already visible words away. Trailing whitespace returns with the complete text.
    public func visibleRuns(shownWords: Int) -> ArraySlice<Run> {
        let count = min(max(0, shownWords), words.count)
        if count == words.count { return runs[...] }
        guard count > 0 else { return runs.prefix(0) }
        return runs.prefix(wordRunEnds[count - 1])
    }

    /// O(1), allocation-free display values for a native shaped text run. The renderer can skip
    /// zero-opacity runs and bypass this entirely once the complete line is settled.
    public func frame(forWord index: Int, shownWords: Int, at now: TimeInterval,
                      reduceMotion: Bool = false, reduceTransparency: Bool = false) -> Frame {
        guard words.indices.contains(index) else { return Frame(opacity: 1, blur: 0) }
        if reduceMotion { return Frame(opacity: 1, blur: 0) }
        guard index < max(0, shownWords) else { return Frame(opacity: 0, blur: 0) }
        guard let start = starts[index], now.isFinite else { return Frame(opacity: 1, blur: 0) }
        let age = now - start
        guard age.isFinite else { return Frame(opacity: 1, blur: 0) }
        if age >= RecordingFeedback.Motion.revealDuration { return Frame(opacity: 1, blur: 0) }
        let reveal = RecordingFeedback.Motion.smoothOut(max(0, age) / RecordingFeedback.Motion.revealDuration)
        return Frame(opacity: reveal, blur: reduceTransparency ? 0 : RecordingFeedback.Motion.revealBlur * (1 - reveal))
    }

    private static func split(_ text: String) -> (runs: [Run], words: [String], wordRunEnds: [Int]) {
        var runs: [Run] = []
        var words: [String] = []
        var ends: [Int] = []
        var start = text.startIndex
        while start < text.endIndex {
            let whitespace = text[start].isWhitespace
            var end = text.index(after: start)
            while end < text.endIndex, text[end].isWhitespace == whitespace { end = text.index(after: end) }
            let piece = String(text[start..<end])
            if whitespace { runs.append(Run(text: piece, wordIndex: nil)) }
            else {
                runs.append(Run(text: piece, wordIndex: words.count))
                words.append(piece)
                ends.append(runs.count)
            }
            start = end
        }
        return (runs, words, ends)
    }
}
