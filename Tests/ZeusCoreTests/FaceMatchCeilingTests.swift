import Foundation
import Testing
@testable import ZeusCore

@Suite struct FaceMatchCeilingTests {
    private func face(_ threshold: Float) -> EnrolledFace {
        EnrolledFace(id: "face-1", name: "Face 1", isEnabled: true, revision: 2,
                     samples: [[1, 0]], threshold: threshold)
    }

    private func seen(_ embedding: [Float]) -> FaceObservation {
        FaceObservation(embedding: embedding, revision: 2)
    }

    @Test func aStoredLimitAboveTheCeilingDoesNotAdmitAStranger() {
        let owner = seen([1, 0])
        let stranger = seen([0, 1])
        #expect(FaceMatch.matches(owner, face: face(10)))
        #expect(!FaceMatch.matches(stranger, face: face(10)))
        #expect(!FaceMatch.matches(owner, face: face(.nan)))
        #expect(!FaceMatch.matches(owner, face: face(-1)))
        #expect(FaceMatch.matches(owner, face: face(0.2)))
        #expect(!FaceMatch.matches(stranger, face: face(0.2)))
    }
}
