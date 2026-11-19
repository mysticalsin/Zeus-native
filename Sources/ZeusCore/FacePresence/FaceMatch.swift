// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): FaceEmbedder.swift, FaceRecognitionPipeline.swift, FaceLabController.swift.
import Foundation

/// What the Vision side read from one frame: the feature print of the aligned face crop as plain numbers, and the
/// revision of the Vision feature print that produced it. No image is carried.
public struct FaceObservation: Equatable, Sendable {
    public let embedding: [Float]
    public let revision: Int

    public init(embedding: [Float], revision: Int) {
        self.embedding = embedding
        self.revision = revision
    }
}

/// One enrolled face: its samples, the centroid of them and the distance limit read from their spread. Samples are
/// kept as unit vectors, and only readable ones of one length are kept, so a half broken record cannot score.
public struct EnrolledFace: Equatable, Sendable {
    public let id: String
    public let name: String
    /// A switched off face is kept but never matched.
    public let isEnabled: Bool
    /// The Vision feature print revision the samples came from. Prints of different revisions are not comparable.
    public let revision: Int
    public let samples: [[Float]]
    /// Unit vector mean of the samples; empty when there are no readable samples.
    public let centroid: [Float]
    /// Largest distance, to the centroid and to the nearest sample, that still counts as this face.
    public let threshold: Float

    public init(id: String, name: String, isEnabled: Bool, revision: Int, samples: [[Float]], threshold: Float) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.revision = revision
        let readable = FaceMatch.readableSamples(samples)
        self.samples = readable
        self.centroid = FaceMatch.average(readable) ?? []
        self.threshold = threshold
    }
}

/// How far one observation is from one enrolled face, by both measures.
public struct FaceScore: Equatable, Sendable {
    public let centroidDistance: Float
    public let nearestSampleDistance: Float
}

/// The answer for one analyzed frame.
public enum FacePresenceVerdict: Equatable, Sendable {
    case owner
    case notOwner

    /// `observation` is the dominant face of the frame already read by the Vision side, or nil when there was no
    /// face or none wide enough to be a candidate (`FaceSelection`). `spoofCues` is `SpoofCues.Window.latched`.
    /// The verdict is `owner` only for a match against an enabled face of the same revision with no spoof cue
    /// latched. Everything else, including a missing face, is `notOwner`: identity only ever withholds a lock.
    public static func decide(observation: FaceObservation?, faces: [EnrolledFace],
                              spoofCues: Set<SpoofCue>) -> FacePresenceVerdict {
        guard let observation, spoofCues.isEmpty else { return .notOwner }
        return FaceMatch.matchingFace(for: observation, in: faces) == nil ? .notOwner : .owner
    }
}

/// Pure vector math and matching on Vision feature prints. Distance is the Euclidean distance between unit
/// vectors, so it runs from 0 (the same print) to 2. Smaller means more alike.
public enum FaceMatch {
    /// The lowest limit a face can get, so a very steady enrollment does not lock the owner out over noise.
    /// First build values: tuned by the owner's calibration check, not by guesswork in code.
    public static let thresholdFloor: Float = 0.25
    /// The highest limit, so a loose enrollment cannot let a stranger through.
    public static let thresholdCeiling: Float = 0.55
    /// How far past the spread of the owner's own samples a frame may sit and still count.
    public static let thresholdFactor: Float = 1.5
    /// Which pairwise distance stands for the spread of the samples.
    public static let spreadPercentile: Float = 0.9

    /// The vector scaled to unit length, or nil when it is empty, holds a value that is not finite or has no length.
    public static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm.isFinite, norm > 0 else { return nil }
        return vector.map { $0 / norm }
    }

    /// Normalize each sample, average, then normalize again. A plain mean would let a longer sample dominate.
    /// The length of the first readable sample decides; unreadable samples and ones of another length are skipped,
    /// and the divisor counts only the samples used.
    public static func average(_ vectors: [[Float]]) -> [Float]? {
        let units = readableSamples(vectors)
        guard let first = units.first else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for unit in units {
            for index in unit.indices { sum[index] += unit[index] }
        }
        return normalized(sum.map { $0 / Float(units.count) })
    }

    /// Euclidean distance between the unit vectors of `a` and `b`. Infinite when either is unreadable or their
    /// lengths differ, so an unreadable pair is never a near one.
    public static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard let unitA = normalized(a), let unitB = normalized(b) else { return .infinity }
        return unitDistance(unitA, unitB)
    }

    /// Scores `observation` against `face`, or nil when the face has no samples or the observation is unreadable
    /// or of another length. Revision and the switch are not looked at here; `matches` does that.
    public static func score(_ observation: FaceObservation, against face: EnrolledFace) -> FaceScore? {
        guard let unit = normalized(observation.embedding), !face.centroid.isEmpty,
              unit.count == face.centroid.count, !face.samples.isEmpty
        else { return nil }
        let nearest = face.samples.map { unitDistance(unit, $0) }.min() ?? .infinity
        return FaceScore(centroidDistance: unitDistance(unit, face.centroid), nearestSampleDistance: nearest)
    }

    /// True only for an enabled face of the same revision where the distance to the centroid and the distance to
    /// the nearest sample are both within the face's threshold.
    public static func matches(_ observation: FaceObservation, face: EnrolledFace) -> Bool {
        guard face.isEnabled, face.revision == observation.revision,
              let score = score(observation, against: face)
        else { return false }
        return score.centroidDistance <= face.threshold && score.nearestSampleDistance <= face.threshold
    }

    /// Among the faces that match, the one whose centroid is nearest. Nil when none matches.
    public static func matchingFace(for observation: FaceObservation, in faces: [EnrolledFace]) -> EnrolledFace? {
        var best: (face: EnrolledFace, distance: Float)?
        for face in faces where matches(observation, face: face) {
            guard let distance = score(observation, against: face)?.centroidDistance else { continue }
            if best == nil || distance < best!.distance { best = (face, distance) }
        }
        return best?.face
    }

    /// The limit for a face enrolled from `samples`: the 90th percentile of the distances between every pair of
    /// samples, times the factor, clamped between the floor and the ceiling. Fewer than two readable samples have
    /// no spread to read, so they get the floor.
    public static func threshold(forSamples samples: [[Float]]) -> Float {
        let units = readableSamples(samples)
        var distances: [Float] = []
        for first in units.indices {
            for second in units.indices where second > first {
                distances.append(unitDistance(units[first], units[second]))
            }
        }
        guard let spread = percentile(distances, spreadPercentile) else { return thresholdFloor }
        return max(thresholdFloor, min(thresholdCeiling, spread * thresholdFactor))
    }

    /// The value at fraction `fraction` (0 to 1) of the sorted values, interpolating between the two nearest ranks.
    static func percentile(_ values: [Float], _ fraction: Float) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = min(max(fraction, 0), 1) * Float(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Float(lower))
    }

    /// The readable samples as unit vectors, all of the length of the first readable one.
    static func readableSamples(_ samples: [[Float]]) -> [[Float]] {
        let units = samples.compactMap(normalized)
        guard let length = units.first?.count else { return [] }
        return units.filter { $0.count == length }
    }

    private static func unitDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var sum: Float = 0
        for index in a.indices {
            let difference = a[index] - b[index]
            sum += difference * difference
        }
        return sum.squareRoot()
    }
}
