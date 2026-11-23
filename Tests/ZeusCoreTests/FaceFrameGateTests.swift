import Testing
@testable import ZeusCore

@Suite("Face frame gate")
struct FaceFrameGateTests {
    @Test func aStaleGenerationDropsTheFrameAndTheSignal() {
        var gate = FaceFrameGate()
        #expect(gate.setCamera(true) == .started(1))
        #expect(gate.accepts(1))
        #expect(gate.accepts(0) == false)
        #expect(gate.failures == 0)
        #expect(gate.setCamera(false) == .stopped)
        #expect(gate.accepts(1) == false)
        #expect(gate.visionFailed() == nil)
    }

    @Test func theFifthVisionFailureFailsTheCameraOnce() {
        var gate = FaceFrameGate()
        #expect(gate.setCamera(true) == .started(1))
        for _ in 1..<FaceFrameGate.failureLimit {
            #expect(gate.visionFailed() == nil)
        }
        #expect(gate.visionFailed() == .failCamera)
        #expect(gate.visionFailed() == nil)
        #expect(gate.visionOk())
        #expect(gate.failures == 0)
        #expect(gate.setCamera(true) == .unchanged)
        #expect(gate.generation == 1)
    }

    @Test func theNextFaceNameReusesADeletedNumber() {
        #expect(FaceNameSequence.next(taken: ["Face 1", "Face 3"]) == "Face 2")
        #expect(FaceNameSequence.next(taken: []) == "Face 1")
    }

    @Test func anEnrollmentOfferForAnotherTokenIsIgnored() {
        var offer = EnrollmentOfferGate()
        #expect(offer.offer(1) == false)
        offer.begin(4)
        #expect(offer.state == .offering(4))
        #expect(offer.offer(4))
        #expect(offer.offer(9) == false)
        offer.end()
        #expect(offer.state == .idle)
        #expect(offer.offer(4) == false)
    }
}
