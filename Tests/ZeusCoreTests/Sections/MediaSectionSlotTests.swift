import Testing

@Suite struct MediaSectionSlotTests {
    @Test func mediaSlotStartsEmpty() {
        let slot = MediaSectionSlot.slot
        #expect(slot.id == "media")
        #expect(slot.title == "Media")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
