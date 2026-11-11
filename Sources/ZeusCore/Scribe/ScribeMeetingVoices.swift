import Foundation

/// The speaker-naming data saved in a meeting file: invitee names and each turn's voice. Kept apart from
/// `ScribeMeetingRecord` so that record stays free of the embedding types.
extension ScribeMeetingRecord.TurnVoice {
    public init(_ turn: ScribeTurnEmbedding) {
        self.init(segmentID: turn.segmentID, source: turn.source == .microphone ? "microphone" : "system",
                  kind: turn.embedding.kind.rawValue,
                  vector: turn.embedding.vector.withUnsafeBufferPointer { Data(buffer: $0) },
                  duration: turn.duration)
    }

    /// Nil when the saved bytes are not a whole, finite vector of a known kind.
    public var turn: ScribeTurnEmbedding? {
        guard let kind = ScribeEmbeddingKind(rawValue: kind), vector.count > 0, vector.count % 4 == 0 else { return nil }
        let count = vector.count / 4
        let values: [Float] = vector.withUnsafeBytes { raw in
            (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
        }
        guard values.allSatisfy(\.isFinite) else { return nil }
        return ScribeTurnEmbedding(segmentID: segmentID, source: source == "microphone" ? .microphone : .system,
                                   embedding: ScribeVoiceEmbedding(kind: kind, vector: values), duration: duration)
    }
}

extension ScribeMeetingRecord {
    /// The saved invitee names, cleaned (never an email address).
    public var attendeeNames: [String] { ScribeAttendeeNames.clean(attendees ?? []) }

    /// The saved turn voices that are still valid vectors.
    public var turnEmbeddings: [ScribeTurnEmbedding] { (turnVoices ?? []).compactMap(\.turn) }
}
