import Testing

@Suite struct GeneralSectionSlotTests {
    @Test func generalSlotStartsEmpty() {
        let slot = GeneralSectionSlot.descriptor
        #expect(slot.id == "glass.general")
        #expect(slot.title == "General")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
