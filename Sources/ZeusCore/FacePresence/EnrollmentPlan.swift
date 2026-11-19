// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): FaceLabController.swift, FaceRecognitionPipeline.swift.
import Foundation

/// How well the face crop was lined up with the template before the feature print was taken.
public enum AlignmentTier: String, CaseIterable, Sendable {
    /// Five landmarks fitted to the template. The only tier good enough to enroll from.
    case fivePoint
    /// Two eye points only.
    case twoPoint
    /// A padded crop of the face box, with no alignment.
    case paddedCrop
}

/// One analyzed frame offered to enrollment. Only numbers: no image.
public struct EnrollmentCandidate: Equatable, Sendable {
    public let embedding: [Float]
    public let revision: Int
    /// Vision's capture quality, 0 to 1, or nil when it gave none.
    public let quality: Float?
    public let alignment: AlignmentTier
    /// The spoof cues latched at this frame.
    public let spoofCues: Set<SpoofCue>

    public init(embedding: [Float], revision: Int, quality: Float?, alignment: AlignmentTier, spoofCues: Set<SpoofCue>) {
        self.embedding = embedding
        self.revision = revision
        self.quality = quality
        self.alignment = alignment
        self.spoofCues = spoofCues
    }
}

/// Pure rules for one enrollment: ten different good samples inside 30 seconds, or nothing is saved. No clock inside:
/// time arrives as `uptime` seconds on every call, so the caller's monotonic clock decides.
public struct EnrollmentPlan: Equatable, Sendable {
    /// Accepted samples that complete an enrollment.
    public static let requiredSamples = 10
    /// Seconds from the start in which they must arrive. A sample at exactly this mark still counts.
    public static let window: Double = 30
    /// Lowest Vision capture quality a sample may have.
    public static let minimumQuality: Float = 0.4
    /// How far a sample must be from the previous accepted one, so ten copies of one frame do not count. First
    /// build value, well under the match floor; tuned by the owner's calibration check.
    public static let minimumSampleDistance: Float = 0.02

    public enum Refusal: Hashable, Sendable {
        /// No face, or none wide enough to be the person at the camera.
        case noFace
        /// A feature print that is empty, not finite, of another length than the first sample, or an unusable time.
        case unreadable
        /// Taken with another Vision revision than the one this enrollment is for.
        case otherRevision
        case spoofed
        /// Aligned by two points or by a padded crop only.
        case weakAlignment
        /// Quality below the minimum, or none given.
        case lowQuality
        /// Too like the previous accepted sample.
        case tooSimilar
    }

    /// What a saved enrollment holds.
    public struct Result: Equatable, Sendable {
        /// The accepted samples as unit vectors.
        public let samples: [[Float]]
        public let revision: Int
        /// The distance limit read from the spread of `samples`.
        public let threshold: Float
    }

    public enum Outcome: Equatable, Sendable {
        case accepted(count: Int)
        case refused(Refusal)
        case completed(Result)
        /// The window closed with fewer than ten samples. Nothing is saved.
        case expired
        /// The plan already completed or expired; the call changed nothing.
        case finished
    }

    public let revision: Int
    public let startedAt: Double
    private var accepted: [[Float]] = []
    private var finishedResult: Result?
    private var hasExpired = false

    public init(revision: Int, startedAt: Double) {
        self.revision = revision
        self.startedAt = startedAt
    }

    public var acceptedCount: Int { accepted.count }
    public var isFinished: Bool { finishedResult != nil || hasExpired }
    /// Set only once ten samples were accepted in time.
    public var result: Result? { finishedResult }

    /// Offers one analyzed frame; nil means the frame had no usable face. The first check is the window, so a late
    /// frame ends the plan instead of sneaking in.
    public mutating func offer(_ candidate: EnrollmentCandidate?, at uptime: Double) -> Outcome {
        if isFinished { return .finished }
        guard uptime.isFinite else { return .refused(.unreadable) }
        if isPastWindow(uptime) {
            hasExpired = true
            return .expired
        }
        guard let candidate else { return .refused(.noFace) }
        guard let unit = FaceMatch.normalized(candidate.embedding) else { return .refused(.unreadable) }
        guard candidate.revision == revision else { return .refused(.otherRevision) }
        guard candidate.spoofCues.isEmpty else { return .refused(.spoofed) }
        guard candidate.alignment == .fivePoint else { return .refused(.weakAlignment) }
        guard let quality = candidate.quality, quality.isFinite, quality >= Self.minimumQuality else {
            return .refused(.lowQuality)
        }
        if let previous = accepted.last {
            guard previous.count == unit.count else { return .refused(.unreadable) }
            guard FaceMatch.distance(previous, unit) >= Self.minimumSampleDistance else { return .refused(.tooSimilar) }
        }

        accepted.append(unit)
        guard accepted.count >= Self.requiredSamples else { return .accepted(count: accepted.count) }
        let saved = Result(samples: accepted, revision: revision, threshold: FaceMatch.threshold(forSamples: accepted))
        finishedResult = saved
        return .completed(saved)
    }

    /// Closes the plan once the window has passed. Returns `.expired` the one time that happens, else nil.
    public mutating func tick(at uptime: Double) -> Outcome? {
        guard !isFinished, uptime.isFinite, isPastWindow(uptime) else { return nil }
        hasExpired = true
        return .expired
    }

    private func isPastWindow(_ uptime: Double) -> Bool {
        uptime - startedAt > Self.window
    }
}
