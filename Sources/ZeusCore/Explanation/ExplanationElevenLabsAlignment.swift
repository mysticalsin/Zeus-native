import Foundation

/// Reads ElevenLabs timestamp alignment into word marks.
///
/// Phase 5 (`docs/POINTING-ASSISTANT-PLAN.md`). A streaming timestamp object
/// carries `alignment.characters`, `character_start_times_seconds` and
/// `character_end_times_seconds`. This reader turns those arrays into word
/// marks with the same fields as `ExplanationAlignmentMark`. It does not open
/// a connection, does not decode audio, and does not estimate a time from a
/// word count. A non-finite time, or a duration that is not a positive finite
/// number, yields no marks.
public enum ExplanationElevenLabsAlignment {
    /// `ExplanationSceneReducer.validate` rejects an alignment longer than this.
    public static let maximumMarks = 4096

    public struct Mark: Equatable, Sendable {
        public var wordIndex: Int
        public var start: Double
        public var end: Double

        public init(wordIndex: Int, start: Double, end: Double) {
            self.wordIndex = wordIndex
            self.start = start
            self.end = end
        }
    }

    public struct Fragment: Equatable, Sendable {
        public var characters: [String]
        public var starts: [Double]
        public var ends: [Double]

        public init(characters: [String], starts: [Double], ends: [Double]) {
            self.characters = characters
            self.starts = starts
            self.ends = ends
        }
    }

    /// One JSON object. Audio bytes are ignored. `normalized_alignment` is ignored.
    /// The result is nil when the object is not that alignment shape, or when the
    /// three arrays differ in length. An empty alignment is an empty fragment.
    public static func fragment(from object: Data) -> Fragment? {
        guard let row = try? JSONDecoder().decode(Payload.self, from: object).alignment else { return nil }
        guard row.characters.count == row.starts.count, row.characters.count == row.ends.count else { return nil }
        return Fragment(characters: row.characters, starts: row.starts, ends: row.ends)
    }

    /// Word marks for one clip. A fragment whose arrays differ in length is left
    /// out. Later fragments are concatenated, then clamped so marks stay inside
    /// `duration` and do not overlap. A restarted fragment is not given an offset.
    public static func marks(from fragments: [Fragment], duration: Double) -> [Mark] {
        guard duration.isFinite, duration > 0 else { return [] }
        var characters: [String] = []
        var starts: [Double] = []
        var ends: [Double] = []
        for fragment in fragments {
            guard fragment.characters.count == fragment.starts.count,
                  fragment.characters.count == fragment.ends.count else { continue }
            characters.append(contentsOf: fragment.characters)
            starts.append(contentsOf: fragment.starts)
            ends.append(contentsOf: fragment.ends)
        }
        guard starts.allSatisfy(\.isFinite), ends.allSatisfy(\.isFinite) else { return [] }

        var marks: [Mark] = []
        var wordStart: Double?
        var wordEnd = 0.0
        var previousEnd = 0.0
        func close() {
            guard let begin = wordStart, marks.count < maximumMarks else { return }
            let start = min(max(begin, previousEnd), duration)
            let end = min(max(wordEnd, start), duration)
            marks.append(Mark(wordIndex: marks.count, start: start, end: end))
            previousEnd = end
            wordStart = nil
        }
        for index in characters.indices {
            if isBreak(characters[index]) {
                close()
                continue
            }
            if wordStart == nil { wordStart = starts[index] }
            wordEnd = ends[index]
        }
        close()
        return marks
    }

    public static func marks(from objects: [Data], duration: Double) -> [Mark] {
        marks(from: objects.compactMap { fragment(from: $0) }, duration: duration)
    }

    /// A token is a break when every scalar is a named blank. An empty token is a
    /// break. U+200B is not a blank, so it stays inside the word. The answer is
    /// read from `ExplanationElevenLabsAlignmentBox`.
    private static func isBreak(_ token: String) -> Bool {
        ExplanationElevenLabsAlignmentBox.isBreak(token)
    }

    private struct Payload: Decodable {
        var alignment: Row?
        struct Row: Decodable {
            var characters: [String]
            var starts: [Double]
            var ends: [Double]
            private enum CodingKeys: String, CodingKey {
                case characters
                case starts = "character_start_times_seconds"
                case ends = "character_end_times_seconds"
            }
        }
    }
}
