import Testing
@testable import ZeusCore

@Suite("Face frame gate")
struct FaceFrameGateTests {
    @Test func aStaleGenerationDropsTheFrameAndTheSignal() {
        var gate = FaceFrameGate()
        let started = gate.setCamera(true)
        #expect(started == .started(1))
        #expect(gate.accepts(1))
        #expect(gate.accepts(0) == false)
        #expect(gate.failures == 0)
        let stopped = gate.setCamera(false)
        #expect(stopped == .stopped)
        #expect(gate.accepts(1) == false)
        let ignored = gate.visionFailed()
        #expect(ignored == nil)
    }

    @Test func theFifthVisionFailureFailsTheCameraOnce() {
        var gate = FaceFrameGate()
        let started = gate.setCamera(true)
        #expect(started == .started(1))
        for _ in 1..<FaceFrameGate.failureLimit {
            let early = gate.visionFailed()
            #expect(early == nil)
        }
        let fifth = gate.visionFailed()
        #expect(fifth == .failCamera)
        let sixth = gate.visionFailed()
        #expect(sixth == nil)
        gate.visionOk()
        #expect(gate.failures == 0)
        let again = gate.setCamera(true)
        #expect(again == .unchanged)
        #expect(gate.generation == 1)
    }

    @Test func theNextFaceNameReusesADeletedNumber() {
        #expect(FaceNameSequence.next(taken: ["Face 1", "Face 3"]) == "Face 2")
        #expect(FaceNameSequence.next(taken: []) == "Face 1")
    }

    @Test func anEnrollmentOfferForAnotherTokenIsIgnored() {
        var offer = EnrollmentOfferGate()
        let idle = offer.offer(1)
        #expect(idle == false)
        offer.begin(4)
        #expect(offer.state == .offering(4))
        let same = offer.offer(4)
        #expect(same)
        let other = offer.offer(9)
        #expect(other == false)
        offer.end()
        #expect(offer.state == .idle)
        let after = offer.offer(4)
        #expect(after == false)
    }
}
