import Foundation

// What one stretch of speech sounds like, as a vector, whichever model made it. The diarizer clusters on these
// and never looks inside: the hand-built voiceprint (always available) and a trained WeSpeaker embedding (after the
// owner clicks Download in Settings) both fit. Nothing here leaves the process and no audio is kept.

public enum ScribeEmbeddingKind: String, Codable, Equatable, Sendable {
    /// `ScribeVoiceprint`: 20 mel bands plus pitch. No download, weaker on similar voices.
    case handBuilt
    /// WeSpeaker, 256 values, L2-normalised, from FluidAudio on the Neural Engine.
    case wespeaker
}

public struct ScribeVoiceEmbedding: Equatable, Sendable {
    public static let wespeakerDimension = 256

    public let kind: ScribeEmbeddingKind
    public let vector: [Float]

    public init(kind: ScribeEmbeddingKind, vector: [Float]) {
        self.kind = kind
        self.vector = vector
    }

    /// Nil when under ~0.8 s of voiced audio, exactly like `ScribeVoiceprint.make`.
    public static func handBuilt(samples: [Float]) -> ScribeVoiceEmbedding? {
        ScribeVoiceprint.make(samples: samples).map { ScribeVoiceEmbedding(kind: .handBuilt, vector: $0.vector) }
    }

    /// A WeSpeaker vector, or nil when it is the wrong size, holds a non-finite value or is all zeros (the
    /// model's answer for audio with no speech in it).
    public static func wespeaker(_ vector: [Float]) -> ScribeVoiceEmbedding? {
        guard vector.count == wespeakerDimension, vector.allSatisfy(\.isFinite), Self.norm(vector) > 1e-6 else { return nil }
        return ScribeVoiceEmbedding(kind: .wespeaker, vector: vector)
    }

    /// Cosine distance for a trained embedding, the voiceprint's own blend for a hand-built one. 0 is the same
    /// voice; 1 or more is unrelated. Vectors of different kinds or sizes are never close (1).
    public func distance(to other: ScribeVoiceEmbedding) -> Float {
        guard kind == other.kind, vector.count == other.vector.count else { return 1 }
        switch kind {
        case .handBuilt:
            return ScribeVoiceprint(vector: vector).distance(to: ScribeVoiceprint(vector: other.vector))
        case .wespeaker:
            let lengthA = Self.norm(vector)
            let lengthB = Self.norm(other.vector)
            guard lengthA > 1e-9, lengthB > 1e-9 else { return 1 }
            var dot: Float = 0
            for index in vector.indices { dot += vector[index] * other.vector[index] }
            return max(0, 1 - dot / (lengthA * lengthB))
        }
    }

    /// Distance up to which two embeddings of this kind are one voice in live clustering.
    /// The hand-built value is the diarizer's long-standing default. The WeSpeaker value starts at 0.5, below
    /// FluidAudio's own 0.65 speaker-match figure so the live pass splits rather than merges; it is an
    /// untuned guess to be adjusted on real meetings.
    public static func defaultThreshold(for kind: ScribeEmbeddingKind) -> Float {
        switch kind {
        case .handBuilt: ScribeDiarizer.defaultThreshold
        case .wespeaker: 0.5
        }
    }

    /// Fewer seconds of audio than this cannot be embedded reliably.
    public static func minimumSeconds(for kind: ScribeEmbeddingKind) -> Double {
        switch kind {
        case .handBuilt: ScribeVoiceprint.minimumVoicedSeconds
        case .wespeaker: 1.0
        }
    }

    private static func norm(_ values: [Float]) -> Float {
        var sum: Float = 0
        for value in values { sum += value * value }
        return sum.squareRoot()
    }
}

/// Turns audio (16 kHz mono) into an embedding, or nil when the chunk is too short or has no speech. The
/// shipped app's implementation wraps a FluidAudio model that is not thread-safe: the owner calls it from one
/// place at a time.
public protocol ScribeVoiceEmbedder {
    var kind: ScribeEmbeddingKind { get }
    func embedding(samples: [Float]) -> ScribeVoiceEmbedding?
}

/// The embedder used when no trained model is on disk: the hand-built voiceprint.
public struct ScribeHandBuiltEmbedder: ScribeVoiceEmbedder {
    public let kind = ScribeEmbeddingKind.handBuilt
    public init() {}
    public func embedding(samples: [Float]) -> ScribeVoiceEmbedding? { .handBuilt(samples: samples) }
}

/// One closed speech turn's voice: it feeds the post-meeting correction and the owner's "Remember this voice".
/// It is saved only inside that meeting's own file (`ScribeMeetingRecord.TurnVoice`, 0600) so naming still works
/// after a relaunch, and goes when the meeting is deleted. Never uploaded, never in the vault.
public struct ScribeTurnEmbedding: Equatable, Sendable {
    public let segmentID: String
    public let source: ScribeAudioSource
    public let embedding: ScribeVoiceEmbedding
    public let duration: TimeInterval

    public init(segmentID: String, source: ScribeAudioSource, embedding: ScribeVoiceEmbedding, duration: TimeInterval) {
        self.segmentID = segmentID
        self.source = source
        self.embedding = embedding
        self.duration = duration
    }
}

public enum ScribeEmbeddingMath {
    /// Duration-weighted mean of same-kind embeddings. Nil for an empty list or mixed kinds.
    public static func centroid(of items: [(embedding: ScribeVoiceEmbedding, weight: Double)]) -> ScribeVoiceEmbedding? {
        guard let first = items.first?.embedding, !first.vector.isEmpty,
              items.allSatisfy({ $0.embedding.kind == first.kind && $0.embedding.vector.count == first.vector.count })
        else { return nil }
        var sum = [Double](repeating: 0, count: first.vector.count)
        var total = 0.0
        for item in items {
            let weight = max(item.weight, 0.001)
            total += weight
            for index in sum.indices { sum[index] += Double(item.embedding.vector[index]) * weight }
        }
        guard total > 0 else { return nil }
        return ScribeVoiceEmbedding(kind: first.kind, vector: sum.map { Float($0 / total) })
    }
}
