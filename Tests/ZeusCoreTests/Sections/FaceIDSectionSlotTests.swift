import Testing

@Suite struct FaceIDSectionSlotTests {
    @Test func faceIDSlotStartsEmpty() {
        let slot = FaceIDSectionSlot.slot
        #expect(slot.id == "faceID")
        #expect(slot.title == "Face ID")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
