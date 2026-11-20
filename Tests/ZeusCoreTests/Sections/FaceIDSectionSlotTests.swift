import Testing
import ZeusCore

@Suite struct FaceIDSectionSlotTests {
    @Test func faceVerificationCardSitsOnPrivacy() {
        let slot = FaceIDSectionSlot.descriptor
        #expect(slot.id == "glass.faceID")
        #expect(slot.title == "Face ID")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.keys.isEmpty)
        #expect(slot.placement == .cardOn(.privacy, 1))
        #expect(GlassSectionManifest.cards(on: .privacy).map(\.id) == ["glass.faceID"])
    }
}
