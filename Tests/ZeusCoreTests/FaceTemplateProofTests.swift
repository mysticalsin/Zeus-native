import Testing
import ZeusCore

@Suite("Face template proof")
struct FaceTemplateProofTests {
    @Test func aConfirmedSaveProofAllowsOnlyASave() {
        let proof = FaceTemplateProof.synthetic(.save, userPresent: true)
        #expect(proof.allows(.save))
        #expect(!proof.allows(.read))
    }

    @Test func aConfirmedReadProofAllowsOnlyARead() {
        let proof = FaceTemplateProof.synthetic(.read, userPresent: true)
        #expect(proof.allows(.read))
        #expect(!proof.allows(.save))
    }

    @Test func anAbsentPersonAllowsNeitherOperation() {
        #expect(!FaceTemplateProof.synthetic(.save, userPresent: false).allows(.save))
        #expect(!FaceTemplateProof.synthetic(.read, userPresent: false).allows(.read))
    }
}
