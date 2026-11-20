import Testing

@Suite struct MediaSectionSlotTests {
    @Test func mediaSlotStartsEmpty() {
        let slot = MediaSectionSlot.descriptor
        #expect(slot.id == "glass.media")
        #expect(slot.title == "Media")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
