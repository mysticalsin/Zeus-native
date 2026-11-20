import Testing
import ZeusCore

@Suite struct FaceIDSectionSlotTests {
    @Test func faceIDSlotStartsEmpty() {
        let slot = FaceIDSectionSlot.descriptor
        #expect(slot.id == "glass.faceID")
        #expect(slot.title == "Face ID")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
