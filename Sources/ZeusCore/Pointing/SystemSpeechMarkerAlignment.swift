import Foundation

/// One marker fact a caller already collected. This type never asks the
/// synthesizer for it.
public struct SystemSpeechMarkerFact: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case word
        case sentence
        case phoneme
    }

    public var kind: Kind
    /// UTF-16 offset of the marked span in the utterance.
    public var utf16Location: Int
    /// UTF-16 length of the marked span.
    public var utf16Length: Int
    /// Seconds from the start of this utterance. The caller measured it.
    public var time: Double

    public init(kind: Kind, utf16Location: Int, utf16Length: Int, time: Double) {
        self.kind = kind
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
        self.time = time
    }
}

/// Word marks from caller-supplied marker facts.
///
/// A fact counts only when its kind is a word and its UTF-16 range is exactly
/// one whitespace-delimited word. The time is the caller's measured time.
/// A word with no word fact is left out. No time is invented from a word count.
/// Sentence and phoneme facts are ignored. Nothing here calls the synthesizer,
/// reads a clock, or opens a connection. The marks are not applied to playback.
public enum SystemSpeechMarkerAlignment {
    public static let maxMarks = 4_096
    public static let maxMarkers = 8_192
    public static let maxTextBytes = 65_536

    public static func wordMarks(
        text: String,
        markers: [SystemSpeechMarkerFact],
        duration: Double
    ) -> [ExplanationAlignmentMark] {
        guard text.utf8.count <= maxTextBytes, markers.count <= maxMarkers,
              duration.isFinite, duration > 0 else { return [] }
        let spans = wordSpans(in: text)
        guard !spans.isEmpty else { return [] }
        var byRange: [RangeKey: Int] = [:]
        byRange.reserveCapacity(spans.count)
        for span in spans where byRange[span.key] == nil {
            byRange[span.key] = span.index
        }
        var chosen: [Int: Choice] = [:]
        for (order, marker) in markers.enumerated() {
            guard marker.kind == .word, marker.time.isFinite, marker.time >= 0, marker.time <= duration,
                  marker.utf16Location >= 0, marker.utf16Length > 0,
                  marker.utf16Location <= Int.max - marker.utf16Length else { continue }
            let key = RangeKey(location: marker.utf16Location, length: marker.utf16Length)
            guard let wordIndex = byRange[key] else { continue }
            let candidate = Choice(time: marker.time, order: order)
            if let existing = chosen[wordIndex] {
                if candidate.time < existing.time || (candidate.time == existing.time && candidate.order < existing.order) {
                    chosen[wordIndex] = candidate
                }
            } else {
                chosen[wordIndex] = candidate
            }
        }
        let kept = chosen.keys.sorted().prefix(maxMarks)
        var marks: [ExplanationAlignmentMark] = []
        var previousEnd = 0.0
        for (offset, wordIndex) in kept.enumerated() {
            guard let choice = chosen[wordIndex] else { continue }
            let nextTime: Double
            if offset + 1 < kept.count, let next = chosen[kept[kept.index(kept.startIndex, offsetBy: offset + 1)]] {
                nextTime = next.time
            } else {
                nextTime = duration
            }
            let start = min(max(choice.time, previousEnd), duration)
            let end = min(max(nextTime, start), duration)
            marks.append(ExplanationAlignmentMark(wordIndex: marks.count, start: start, end: end))
            previousEnd = end
        }
        return marks
    }

    private struct RangeKey: Hashable {
        var location: Int
        var length: Int
    }

    private struct WordSpan {
        var index: Int
        var key: RangeKey
    }

    private struct Choice {
        var time: Double
        var order: Int
    }

    private static func wordSpans(in text: String) -> [WordSpan] {
        let units = Array(text.utf16)
        var spans: [WordSpan] = []
        var index = 0
        while index < units.count {
            guard let (first, width) = readScalar(in: units, at: index) else { break }
            if first.properties.isWhitespace {
                index += width
                continue
            }
            let start = index
            index += width
            while index < units.count, let (next, nextWidth) = readScalar(in: units, at: index), !next.properties.isWhitespace {
                index += nextWidth
            }
            spans.append(WordSpan(index: spans.count, key: RangeKey(location: start, length: index - start)))
        }
        return spans
    }

    private static func readScalar(in units: [UInt16], at index: Int) -> (Unicode.Scalar, Int)? {
        guard index < units.count else { return nil }
        let unit = UInt32(units[index])
        if !(0xD800...0xDFFF).contains(unit) {
            return (Unicode.Scalar(unit) ?? Unicode.Scalar(0xFFFD)!, 1)
        }
        if (0xD800...0xDBFF).contains(unit), index + 1 < units.count {
            let low = UInt32(units[index + 1])
            if (0xDC00...0xDFFF).contains(low) {
                let value = ((unit - 0xD800) << 10) + (low - 0xDC00) + 0x10000
                return (Unicode.Scalar(value) ?? Unicode.Scalar(0xFFFD)!, 2)
            }
        }
        return (Unicode.Scalar(0xFFFD)!, 1)
    }
}
