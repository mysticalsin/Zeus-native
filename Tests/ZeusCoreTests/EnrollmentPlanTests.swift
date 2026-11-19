import Foundation
import Testing
@testable import ZeusCore

@Suite("Enrollment plan")
struct EnrollmentPlanTests {
    private let revision = 2

    /// A unit vector in the plane `degrees` from the x axis; samples a few degrees apart are distinct frames.
    private func planar(_ degrees: Float) -> [Float] {
        let radians = degrees * .pi / 180
        return [cos(radians), sin(radians)]
    }

    private func candidate(_ degrees: Float, quality: Float? = 0.9, alignment: AlignmentTier = .fivePoint,
                           cues: Set<SpoofCue> = [], revision: Int? = nil) -> EnrollmentCandidate {
        EnrollmentCandidate(embedding: planar(degrees), revision: revision ?? self.revision, quality: quality,
                            alignment: alignment, spoofCues: cues)
    }

    private func newPlan(startedAt: Double = 100) -> EnrollmentPlan {
        EnrollmentPlan(revision: revision, startedAt: startedAt)
    }

    /// Feeds `count` distinct good samples, one every `step` seconds from the plan's start, and returns the last outcome.
    @discardableResult
    private func feed(_ plan: inout EnrollmentPlan, count: Int, step: Double = 2, from: Double = 100)
        -> EnrollmentPlan.Outcome {
        var outcome: EnrollmentPlan.Outcome = .finished
        for index in 0..<count {
            outcome = plan.offer(candidate(Float(index) * 4), at: from + step * Double(index))
        }
        return outcome
    }

    @Test func tenDistinctSamplesInTimeComplete() throws {
        var plan = newPlan()
        for index in 0..<9 {
            let outcome = plan.offer(candidate(Float(index) * 4), at: 100 + Double(index) * 3)
            #expect(outcome == .accepted(count: index + 1))
        }
        #expect(!plan.isFinished)
        #expect(plan.result == nil)

        // The tenth lands exactly on the 30 second mark, which still counts.
        let last = plan.offer(candidate(36), at: 130)
        guard case .completed(let result) = last else {
            Issue.record("expected completion, got \(last)")
            return
        }
        #expect(result.samples.count == EnrollmentPlan.requiredSamples)
        #expect(result.revision == revision)
        #expect(plan.isFinished)
        #expect(plan.result == result)
        // Saved samples are unit vectors, and the threshold comes from their spread inside the clamp.
        #expect(result.samples.allSatisfy { abs($0.reduce(0) { $0 + $1 * $1 } - 1) < 1e-5 })
        #expect(result.threshold == FaceMatch.threshold(forSamples: result.samples))
        #expect(result.threshold >= FaceMatch.thresholdFloor)
        #expect(result.threshold <= FaceMatch.thresholdCeiling)

        // A finished plan takes nothing more, so a late frame cannot grow the saved set.
        do { let outcome = plan.offer(candidate(80), at: 131); #expect(outcome == .finished) }
        #expect(plan.result?.samples.count == EnrollmentPlan.requiredSamples)
    }

    @Test func nineSamplesSaveNothing() {
        var plan = newPlan()
        for index in 0..<9 {
            do { let outcome = plan.offer(candidate(Float(index) * 4), at: 100 + Double(index) * 3); #expect(outcome == .accepted(count: index + 1)) }
        }
        #expect(plan.acceptedCount == 9)
        #expect(plan.result == nil)

        // Nothing happens before the window closes, then the plan expires once and holds no result.
        do { let outcome = plan.tick(at: 129.9); #expect(outcome == nil) }
        do { let outcome = plan.tick(at: 130.1); #expect(outcome == .expired) }
        #expect(plan.isFinished)
        #expect(plan.result == nil)
        do { let outcome = plan.tick(at: 200); #expect(outcome == nil) }

        // A tenth good sample that arrives after the window is not accepted.
        do { let outcome = plan.offer(candidate(36), at: 131); #expect(outcome == .finished) }
        #expect(plan.result == nil)

        // The same holds when the late frame itself notices the window closed.
        var late = newPlan()
        feed(&late, count: 9, step: 1)
        do { let outcome = late.offer(candidate(36), at: 130.5); #expect(outcome == .expired) }
        #expect(late.result == nil)
    }

    @Test func duplicateFramesDoNotCount() {
        var plan = newPlan()
        do { let outcome = plan.offer(candidate(0), at: 100); #expect(outcome == .accepted(count: 1)) }
        // Ten copies of one frame add nothing.
        for index in 1...10 {
            do { let outcome = plan.offer(candidate(0), at: 100 + Double(index)); #expect(outcome == .refused(.tooSimilar)) }
        }
        #expect(plan.acceptedCount == 1)
        // A hair under the minimum distance from the previous sample is still the same frame.
        let tinyStep = 2 * asin(EnrollmentPlan.minimumSampleDistance * 0.5 / 2) * 180 / .pi
        do { let outcome = plan.offer(candidate(tinyStep), at: 111); #expect(outcome == .refused(.tooSimilar)) }
        // A real change is accepted, and only the previous sample is compared: going back is allowed.
        do { let outcome = plan.offer(candidate(10), at: 112); #expect(outcome == .accepted(count: 2)) }
        do { let outcome = plan.offer(candidate(0), at: 113); #expect(outcome == .accepted(count: 3)) }
        // Ten refused copies never complete a plan.
        #expect(!plan.isFinished)
        #expect(plan.result == nil)
    }

    @Test func lowQualityAndTwoPointSamplesAreRefused() {
        var plan = newPlan()
        do { let outcome = plan.offer(candidate(0, quality: 0.39), at: 101); #expect(outcome == .refused(.lowQuality)) }
        do { let outcome = plan.offer(candidate(0, quality: nil), at: 102); #expect(outcome == .refused(.lowQuality)) }
        do { let outcome = plan.offer(candidate(0, quality: .nan), at: 103); #expect(outcome == .refused(.lowQuality)) }
        do { let outcome = plan.offer(candidate(0, alignment: .twoPoint), at: 104); #expect(outcome == .refused(.weakAlignment)) }
        do { let outcome = plan.offer(candidate(0, alignment: .paddedCrop), at: 105); #expect(outcome == .refused(.weakAlignment)) }
        #expect(plan.acceptedCount == 0)

        // The quality floor itself is accepted.
        do { let outcome = plan.offer(candidate(0, quality: EnrollmentPlan.minimumQuality), at: 106); #expect(outcome == .accepted(count: 1)) }
        #expect(EnrollmentPlan.minimumQuality == 0.4)
    }

    @Test func aSpoofCueRefusesTheSample() {
        var plan = newPlan()
        do { let outcome = plan.offer(candidate(0, cues: [.glossGlare]), at: 101); #expect(outcome == .refused(.spoofed)) }
        do { let outcome = plan.offer(candidate(0, cues: [.deviceBezel]), at: 102); #expect(outcome == .refused(.spoofed)) }
        #expect(plan.acceptedCount == 0)
        do { let outcome = plan.offer(candidate(0), at: 103); #expect(outcome == .accepted(count: 1)) }
    }

    @Test func noFaceUnreadableAndOtherRevisionSamplesAreRefused() {
        var plan = newPlan()
        do { let outcome = plan.offer(nil, at: 101); #expect(outcome == .refused(.noFace)) }
        let unreadable = EnrollmentCandidate(embedding: [.nan, 1], revision: revision, quality: 0.9,
                                             alignment: .fivePoint, spoofCues: [])
        do { let outcome = plan.offer(unreadable, at: 102); #expect(outcome == .refused(.unreadable)) }
        let empty = EnrollmentCandidate(embedding: [], revision: revision, quality: 0.9, alignment: .fivePoint,
                                        spoofCues: [])
        do { let outcome = plan.offer(empty, at: 103); #expect(outcome == .refused(.unreadable)) }
        do { let outcome = plan.offer(candidate(0, revision: revision + 1), at: 104); #expect(outcome == .refused(.otherRevision)) }
        do { let outcome = plan.offer(candidate(0), at: .nan); #expect(outcome == .refused(.unreadable)) }
        #expect(plan.acceptedCount == 0)

        // A vector of another length than the first accepted one is unreadable, not a sample.
        do { let outcome = plan.offer(candidate(0), at: 105); #expect(outcome == .accepted(count: 1)) }
        let longer = EnrollmentCandidate(embedding: [1, 0, 0], revision: revision, quality: 0.9,
                                         alignment: .fivePoint, spoofCues: [])
        do { let outcome = plan.offer(longer, at: 106); #expect(outcome == .refused(.unreadable)) }
        #expect(plan.acceptedCount == 1)
    }

    @Test func refusalsDoNotSpendTheWindowOrTheCount() {
        // Lots of refused frames, then ten good ones inside the window: still completes.
        var plan = newPlan()
        for index in 0..<20 {
            do { let outcome = plan.offer(candidate(0, quality: 0.1), at: 100 + Double(index) * 0.5); #expect(outcome == .refused(.lowQuality)) }
        }
        var outcome: EnrollmentPlan.Outcome = .finished
        for index in 0..<10 {
            outcome = plan.offer(candidate(Float(index) * 4), at: 112 + Double(index) * 0.5)
        }
        guard case .completed(let result) = outcome else {
            Issue.record("expected completion, got \(outcome)")
            return
        }
        #expect(result.samples.count == 10)
    }

    @Test func theNamedConstantsMatchThePlan() {
        #expect(EnrollmentPlan.requiredSamples == 10)
        #expect(EnrollmentPlan.window == 30)
        #expect(EnrollmentPlan.minimumSampleDistance > 0)
        #expect(EnrollmentPlan.minimumSampleDistance < FaceMatch.thresholdFloor)
    }
}
