import Foundation

/// Extracts complete top-level JSON objects from a byte stream, however the server frames them
/// (newline delimited, `data:` prefixed, or back to back). Anything outside an object is skipped.
/// Bounded: one object may not exceed `maxObjectBytes`.
public struct JSONObjectSplitter: Sendable {
    public static let maxObjectBytes = 4_194_304
    private var current: [UInt8] = []
    private var depth = 0
    private var inString = false
    private var escaped = false

    public init() {}

    public enum Failure: Error, Equatable, Sendable { case objectTooLarge }

    public mutating func append(_ bytes: Data) throws -> [Data] {
        var objects: [Data] = []
        for byte in bytes {
            if depth == 0 {
                guard byte == 123 else { continue }
                depth = 1; current = [byte]; inString = false; escaped = false
                continue
            }
            current.append(byte)
            guard current.count <= Self.maxObjectBytes else { depth = 0; current = []; throw Failure.objectTooLarge }
            if inString {
                if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { inString = false }
                continue
            }
            switch byte {
            case 34: inString = true
            case 123: depth += 1
            case 125:
                depth -= 1
                if depth == 0 { objects.append(Data(current)); current = [] }
            default: break
            }
        }
        return objects
    }

    /// True when a partial object is pending (the stream ended mid-object).
    public var hasPartial: Bool { depth > 0 }
}

/// One chunk of the ElevenLabs text-to-speech streaming-with-timestamps response.
/// Shape verified 2026-11-10 against
/// https://elevenlabs.io/docs/api-reference/text-to-speech/stream-with-timestamps :
/// `audio_base64`, `alignment` and `normalized_alignment`, each alignment holding
/// `characters`, `character_start_times_seconds`, `character_end_times_seconds`.
public struct ElevenLabsTimestampChunk: Decodable, Sendable {
    public struct Alignment: Decodable, Sendable {
        public var characters: [String]
        public var starts: [Double]
        public var ends: [Double]
        private enum CodingKeys: String, CodingKey {
            case characters
            case starts = "character_start_times_seconds"
            case ends = "character_end_times_seconds"
        }
    }
    public var audio: Data
    public var alignment: Alignment?

    private enum CodingKeys: String, CodingKey { case audioBase64 = "audio_base64", alignment }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = try c.decodeIfPresent(String.self, forKey: .audioBase64) ?? ""
        guard let data = Data(base64Encoded: text) else {
            throw DecodingError.dataCorruptedError(forKey: .audioBase64, in: c, debugDescription: "audio_base64")
        }
        audio = data
        alignment = try c.decodeIfPresent(Alignment.self, forKey: .alignment)
    }
}

public enum PointingSpeechAlignment {
    /// Word marks from character timings. Words split on whitespace; a word's start is its first
    /// character's start and its end is its last character's end. Times are clamped to be
    /// non-overlapping and not past `duration`, and invalid input yields no marks (the caller then
    /// falls back to start/end anchors; it must never estimate timing from word counts).
    public static func wordMarks(characters: [String], starts: [Double], ends: [Double],
                                 duration: Double) -> [ExplanationAlignmentMark] {
        guard characters.count == starts.count, characters.count == ends.count, duration.isFinite, duration > 0,
              starts.allSatisfy(\.isFinite), ends.allSatisfy(\.isFinite) else { return [] }
        var marks: [ExplanationAlignmentMark] = []
        var wordStart: Double?, wordEnd = 0.0, previousEnd = 0.0
        func close() {
            guard let begin = wordStart, marks.count <= 4096 else { return }
            let start = min(max(begin, previousEnd), duration)
            let end = min(max(wordEnd, start), duration)
            marks.append(ExplanationAlignmentMark(wordIndex: marks.count, start: start, end: end))
            previousEnd = end; wordStart = nil
        }
        for index in characters.indices {
            let isSpace = characters[index].allSatisfy { $0.isWhitespace }
            if isSpace { close(); continue }
            if wordStart == nil { wordStart = starts[index] }
            wordEnd = ends[index]
        }
        close()
        return marks
    }
}
