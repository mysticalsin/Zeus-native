import Foundation

/// One recognition segment the caller already has.
///
/// `start` is seconds from the beginning of the audio. Nil means the engine
/// gave no time. Duration is not a field: spreading it across the words would
/// invent times from a word count. This type never asks a recognizer for a segment.
public struct SpeechSegmentFact: Equatable, Sendable {
    public var text: String
    public var start: Double?

    public init(text: String, start: Double?) {
        self.text = text
        self.start = start
    }
}

/// One whitespace-delimited word taken from a segment.
///
/// `start` is that segment's measured start, or nil when the segment had no
/// usable time. A later segment does not fill an earlier word.
public struct SpeechSegmentWord: Equatable, Sendable {
    public var text: String
    public var start: Double?

    public init(text: String, start: Double?) {
        self.text = text
        self.start = start
    }
}

/// Words from caller-supplied recognition segments.
///
/// Each word keeps the start of its own segment. Words in one segment share
/// that start. A missing, negative, or non-finite start stays unset. No time
/// is invented from a word count, from a neighbour, or from a clock. The split
/// is on whitespace, so punctuation stays on its token and U+200B is not a break.
/// Nothing here calls a recognizer, reads a clock, or opens a connection.
/// The words are not applied to deixis.
public enum SpeechSegmentWords {
    public static let maxWords = 4_096
    public static let maxSegments = 8_192
    public static let maxTextBytes = 65_536

    public static func words(from segments: [SpeechSegmentFact]) -> [SpeechSegmentWord] {
        guard withinBudget(segments) else { return [] }
        var out: [SpeechSegmentWord] = []
        out.reserveCapacity(min(maxWords, 64))
        for segment in segments {
            let start = measuredStart(segment.start)
            for token in segment.text.split(whereSeparator: { $0.isWhitespace }) {
                if out.count == maxWords { return out }
                out.append(SpeechSegmentWord(text: String(token), start: start))
            }
        }
        return out
    }

    private static func withinBudget(_ segments: [SpeechSegmentFact]) -> Bool {
        guard segments.count <= maxSegments else { return false }
        var bytes = 0
        for segment in segments {
            let count = segment.text.utf8.count
            if count > maxTextBytes - bytes { return false }
            bytes += count
        }
        return true
    }

    private static func measuredStart(_ start: Double?) -> Double? {
        guard let start, start.isFinite, start >= 0 else { return nil }
        return start
    }
}
