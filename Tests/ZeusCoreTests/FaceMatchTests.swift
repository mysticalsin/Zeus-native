import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Face match")
struct FaceMatchTests {
    /// A unit vector in the plane at `degrees` from the x axis. Two of them `d` apart in chord length differ by
    /// `2 * asin(d / 2)` radians, which lets a test ask for an exact distance.
    private func planar(_ degrees: Float) -> [Float] {
        let radians = degrees * .pi / 180
        return [cos(radians), sin(radians)]
    }

    private func degrees(forChord chord: Float) -> Float {
        2 * asin(chord / 2) * 180 / .pi
    }

    private func face(_ samples: [[Float]], enabled: Bool = true, revision: Int = 2, threshold: Float = 0.5,
                      id: String = "face-1") -> EnrolledFace {
        EnrolledFace(id: id, name: "Face 1", isEnabled: enabled, revision: revision, samples: samples,
                     threshold: threshold)
    }

    private func observation(_ embedding: [Float], revision: Int = 2) -> FaceObservation {
        FaceObservation(embedding: embedding, revision: revision)
    }

    /// Three samples whose centroid sits in the middle of the cloud and each sample on a different axis.
    private var spread: [[Float]] { [[1, 0, 0], [0, 1, 0], [0, 0, 1]] }

    @Test func averageNormalizesEachSampleFirst() throws {
        // [30, 0] is ten times longer than [0, 3]. A plain mean would lean towards the long one; normalizing each
        // sample first gives the diagonal.
        let mean = try #require(FaceMatch.average([[30, 0], [0, 3]]))
        let diagonal: Float = 1 / Float(2).squareRoot()
        #expect(abs(mean[0] - diagonal) < 1e-5)
        #expect(abs(mean[1] - diagonal) < 1e-5)
        // The result is unit length.
        #expect(abs(mean.reduce(0) { $0 + $1 * $1 } - 1) < 1e-5)

        // Empty input, an empty vector and an all-zero vector have no average.
        #expect(FaceMatch.average([]) == nil)
        #expect(FaceMatch.average([[]]) == nil)
        #expect(FaceMatch.average([[0, 0, 0]]) == nil)
        // A sample of another length or with a NaN is skipped, and the divisor follows the samples used.
        let skipped = try #require(FaceMatch.average([[1, 0], [1, 0, 0], [.nan, 1], [1, 0]]))
        #expect(skipped == [1, 0])
    }

    @Test func distanceIsBetweenUnitVectors() {
        #expect(FaceMatch.distance([2, 0], [5, 0]) == 0)
        #expect(abs(FaceMatch.distance([1, 0], [0, 1]) - Float(2).squareRoot()) < 1e-5)
        #expect(abs(FaceMatch.distance([1, 0], [-1, 0]) - 2) < 1e-5)
        // Unreadable pairs are infinitely far, never zero.
        #expect(FaceMatch.distance([1, 0], [1, 0, 0]) == .infinity)
        #expect(FaceMatch.distance([], []) == .infinity)
        #expect(FaceMatch.distance([0, 0], [1, 0]) == .infinity)
        #expect(FaceMatch.distance([.infinity, 0], [1, 0]) == .infinity)
    }

    @Test func matchNeedsCentroidAndNearestSample() {
        // Close to one sample, far from the centroid of three: the nearest sample alone is not enough.
        let cloud = face(spread)
        let onOneSample = observation([1, 0, 0])
        let score = FaceMatch.score(onOneSample, against: cloud)
        #expect(score?.nearestSampleDistance == 0)
        #expect((score?.centroidDistance ?? 0) > 0.8)
        #expect(!FaceMatch.matches(onOneSample, face: cloud))

        // Dead on the centroid but far from both samples: the centroid alone is not enough either.
        let pair = face([[1, 1, 0], [1, -1, 0]])
        let onCentroid = observation([1, 0, 0])
        let pairScore = FaceMatch.score(onCentroid, against: pair)
        #expect((pairScore?.centroidDistance ?? 1) < 1e-5)
        #expect((pairScore?.nearestSampleDistance ?? 0) > 0.7)
        #expect(!FaceMatch.matches(onCentroid, face: pair))

        // Near the centroid and near a sample: a match. The threshold is inclusive.
        let tight = face([planar(0), planar(10), planar(20)])
        #expect(FaceMatch.matches(observation(planar(10)), face: tight))
        let limit = FaceMatch.distance(planar(0), planar(30))
        let edge = face([planar(0)], threshold: limit + 1e-4)
        #expect(FaceMatch.matches(observation(planar(30)), face: edge))
        #expect(!FaceMatch.matches(observation(planar(31)), face: edge))
        // Exactly at the threshold is inside it.
        #expect(FaceMatch.matches(observation([1, 0]), face: face([[1, 0]], threshold: 0)))

        // A vector of another length, or an unreadable one, is not scored at all.
        #expect(FaceMatch.score(observation([1, 0]), against: cloud) == nil)
        #expect(FaceMatch.score(observation([]), against: cloud) == nil)
        #expect(!FaceMatch.matches(observation([.nan, 0, 0]), face: cloud))
    }

    @Test func aStoredLimitAboveTheCeilingDoesNotAdmitAStranger() {
        let owner = observation([1, 0])
        let stranger = observation([0, 1])
        #expect(FaceMatch.matches(owner, face: face([[1, 0]], threshold: 10)))
        #expect(!FaceMatch.matches(stranger, face: face([[1, 0]], threshold: 10)))
        #expect(!FaceMatch.matches(owner, face: face([[1, 0]], threshold: .nan)))
        #expect(!FaceMatch.matches(owner, face: face([[1, 0]], threshold: -1)))
    }

    @Test func aSwitchedOffFaceNeverMatches() {
        let samples = [planar(0), planar(5), planar(10)]
        let seen = observation(planar(5))
        let on = face(samples, enabled: true)
        let off = face(samples, enabled: false, id: "face-off")
        #expect(FaceMatch.matches(seen, face: on))
        #expect(!FaceMatch.matches(seen, face: off))
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [on], spoofCues: []) == .owner)
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [off], spoofCues: []) == .notOwner)

        // Another enabled face does not help the switched-off one, and the switched-off one does not hide it.
        let other = face([planar(90)], id: "face-2")
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [off, other], spoofCues: []) == .notOwner)
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [off, on], spoofCues: []) == .owner)
        #expect(FaceMatch.matchingFace(for: seen, in: [off, on])?.id == on.id)
        #expect(FaceMatch.matchingFace(for: seen, in: [off]) == nil)
    }

    @Test func samplesFromAnotherRevisionNeverMatch() {
        let samples = [planar(0), planar(5), planar(10)]
        let old = face(samples, revision: 1)
        let current = face(samples, revision: 2)
        let seen = observation(planar(5), revision: 2)
        #expect(!FaceMatch.matches(seen, face: old))
        #expect(FaceMatch.matches(seen, face: current))
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [old], spoofCues: []) == .notOwner)
        // Identical numbers from a newer revision are no better: only equal revisions compare.
        let newer = observation(planar(5), revision: 3)
        #expect(!FaceMatch.matches(newer, face: current))
        #expect(FacePresenceVerdict.decide(observation: newer, faces: [current], spoofCues: []) == .notOwner)
    }

    @Test func aSpoofCueTurnsAMatchIntoNotOwner() {
        let enrolled = face([planar(0), planar(5), planar(10)])
        let seen = observation(planar(5))
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [enrolled], spoofCues: []) == .owner)
        for cue in SpoofCue.allCases {
            #expect(FacePresenceVerdict.decide(observation: seen, faces: [enrolled], spoofCues: [cue]) == .notOwner)
        }
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [enrolled], spoofCues: [.glossGlare, .deviceBezel])
                == .notOwner)

        // Wired to the real window: three counted glare frames of the last six latch it, and it ages out.
        var window = SpoofCues.Window()
        let glass = SpoofFrame(glare: GlareSample(cropPixelWidth: 130, specularFraction: 0.08,
                                                  specularClusterRatio: 1.0), deviceOverlapFraction: nil)
        let clean = SpoofFrame(glare: nil, deviceOverlapFraction: nil)
        for _ in 0..<3 { window.observe(glass) }
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [enrolled], spoofCues: window.latched) == .notOwner)
        for _ in 0..<6 { window.observe(clean) }
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [enrolled], spoofCues: window.latched) == .owner)
    }

    @Test func noFaceIsNotOwner() {
        let enrolled = face([planar(0), planar(5), planar(10)])
        #expect(FacePresenceVerdict.decide(observation: nil, faces: [enrolled], spoofCues: []) == .notOwner)
        #expect(FacePresenceVerdict.decide(observation: observation(planar(5)), faces: [], spoofCues: []) == .notOwner)
        #expect(FacePresenceVerdict.decide(observation: nil, faces: [], spoofCues: []) == .notOwner)

        // A face with no samples has no centroid and never matches, whatever the observation is.
        let empty = face([])
        #expect(!FaceMatch.matches(observation(planar(5)), face: empty))
        #expect(FacePresenceVerdict.decide(observation: observation(planar(5)), faces: [empty], spoofCues: []) == .notOwner)

        // A bystander below the width floor is no candidate, so the caller has no observation to give.
        let bystander = CGRect(x: 0.4, y: 0.4, width: FaceSelection.minimumWidth - 0.01, height: 0.2)
        let selected = FaceSelection.select(in: [bystander], preferNear: nil)
        #expect(selected == nil)
        let seen: FaceObservation? = selected.map { _ in observation(planar(5)) }
        #expect(FacePresenceVerdict.decide(observation: seen, faces: [enrolled], spoofCues: []) == .notOwner)
    }

    @Test func thresholdComesFromTheSamplesAndIsClamped() {
        func threshold(spreadChord chord: Float) -> Float {
            FaceMatch.threshold(forSamples: [planar(0), planar(degrees(forChord: chord))])
        }
        // Very similar samples: the floor, so a steady owner is not locked out by an over-tight limit.
        #expect(threshold(spreadChord: 0.05) == FaceMatch.thresholdFloor)
        // In the middle the limit is the spread times the factor.
        let middle = FaceMatch.thresholdFloor / FaceMatch.thresholdFactor
            + (FaceMatch.thresholdCeiling - FaceMatch.thresholdFloor) / FaceMatch.thresholdFactor / 2
        #expect(abs(threshold(spreadChord: middle) - middle * FaceMatch.thresholdFactor) < 1e-4)
        // Very different samples: the ceiling, so a loose enrollment cannot let a stranger through.
        #expect(threshold(spreadChord: 1.2) == FaceMatch.thresholdCeiling)
        // Fewer than two samples have no spread to read.
        #expect(FaceMatch.threshold(forSamples: []) == FaceMatch.thresholdFloor)
        #expect(FaceMatch.threshold(forSamples: [planar(0)]) == FaceMatch.thresholdFloor)
        // The clamp is ordered, and the values are the ones the plan names for the first build.
        #expect(FaceMatch.thresholdFloor < FaceMatch.thresholdCeiling)
        #expect(FaceMatch.thresholdFactor == 1.5)
        #expect(FaceMatch.spreadPercentile == 0.9)

        // Nine tight samples keep the floor. One stray sample is nine of the 45 pairs, which is more than the top
        // tenth that the percentile ignores, so it widens the limit up to the ceiling and no further.
        var cluster = (0..<9).map { planar(Float($0)) }
        #expect(FaceMatch.threshold(forSamples: cluster) == FaceMatch.thresholdFloor)
        cluster.append(planar(60))
        #expect(FaceMatch.threshold(forSamples: cluster) == FaceMatch.thresholdCeiling)
    }

    @Test func percentileInterpolatesBetweenRanks() {
        #expect(FaceMatch.percentile([], 0.9) == nil)
        #expect(FaceMatch.percentile([4], 0.9) == 4)
        #expect(FaceMatch.percentile([1, 2, 3, 4, 5], 0.5) == 3)
        #expect(FaceMatch.percentile([5, 1, 3, 2, 4], 1.0) == 5)
        #expect(FaceMatch.percentile([5, 1, 3, 2, 4], 0.0) == 1)
        let p90 = FaceMatch.percentile([0, 10], 0.9)
        #expect(abs((p90 ?? 0) - 9) < 1e-5)
    }

    @Test func theBestMatchingFaceWinsAmongSeveral() {
        let near = face([planar(0), planar(10)], id: "near")
        let nearer = face([planar(1), planar(3)], id: "nearer")
        let far = face([planar(80)], id: "far")
        let seen = observation(planar(2))
        #expect(FaceMatch.matchingFace(for: seen, in: [far, near, nearer])?.id == "nearer")
        #expect(FaceMatch.matchingFace(for: observation(planar(170)), in: [far, near, nearer]) == nil)
    }

    @Test func aFaceKeepsOnlyReadableSamplesOfOneLength() {
        let mixed = face([[1, 0], [0, 0], [1, 0, 0], [.nan, 1], [0, 1]])
        #expect(mixed.samples.count == 2)
        #expect(mixed.samples.allSatisfy { $0.count == 2 })
        let unit = mixed.samples.map { $0.reduce(0) { $0 + $1 * $1 } }
        #expect(unit.allSatisfy { abs($0 - 1) < 1e-5 })
        #expect(mixed.centroid.count == 2)
    }
}
