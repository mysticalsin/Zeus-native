import Foundation

/// Who spoke, and for how long, from a meeting's transcript. Pure: the finished notes, the recap view and
/// tests all read the same numbers.
public struct ScribeSpeakerStats: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let speaker: ScribeSpeaker
        /// Sum of `end - start` over this speaker's segments, never negative.
        public let talkSeconds: TimeInterval
        /// This speaker's part of the whole, 0...1. Talk time decides; when no segment has any length, the
        /// count of segments does.
        public let share: Double
        public let segmentCount: Int
    }

    /// One entry per speaker, in the order each first appears in the transcript.
    public let speakers: [Entry]

    /// Segments with empty (or whitespace-only) text are ignored.
    public init(segments: [ScribeTranscriptSegment]) {
        var order: [ScribeSpeaker] = []
        var seconds: [ScribeSpeaker: TimeInterval] = [:]
        var counts: [ScribeSpeaker: Int] = [:]
        for segment in segments where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if counts[segment.speaker] == nil { order.append(segment.speaker) }
            let length = segment.end - segment.start
            seconds[segment.speaker, default: 0] += length.isFinite ? max(0, length) : 0
            counts[segment.speaker, default: 0] += 1
        }
        let totalSeconds = seconds.values.reduce(0, +)
        let totalSegments = counts.values.reduce(0, +)
        speakers = order.map { speaker in
            let talk = seconds[speaker] ?? 0
            let count = counts[speaker] ?? 0
            let share: Double
            if totalSeconds > 0 {
                share = talk / totalSeconds
            } else {
                share = totalSegments > 0 ? Double(count) / Double(totalSegments) : 0
            }
            return Entry(speaker: speaker, talkSeconds: talk, share: min(1, max(0, share)), segmentCount: count)
        }
    }

    public var totalTalkSeconds: TimeInterval { speakers.reduce(0) { $0 + $1.talkSeconds } }

    /// False for a lone speaker with no measured talk time (nothing worth a "Speakers" section).
    public var isWorthShowing: Bool {
        speakers.count > 1 || (speakers.first?.talkSeconds ?? 0) > 0
    }

    /// Talk time as m:ss (minutes keep counting past 59).
    public static func format(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? Int(max(0, seconds).rounded()) : 0
        let rest = whole % 60
        return "\(whole / 60):\(rest < 10 ? "0" : "")\(rest)"
    }
}

/// The closed-notch ticker's text: the newest words of a segment, nothing else.
public enum ScribeTickerText {
    /// The "…" a segment shows before its words arrive is not text anyone can read.
    public static func hasWords(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "…"
    }

    /// The last `words` words, joined by single spaces. All of them when there are fewer.
    public static func tail(_ text: String, words: Int) -> String {
        let all = text.split(whereSeparator: \.isWhitespace)
        guard words > 0 else { return "" }
        return all.suffix(words).joined(separator: " ")
    }
}
