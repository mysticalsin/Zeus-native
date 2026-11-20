import Testing

@Suite struct GeneralSectionSlotTests {
    @Test func generalSlotStartsEmpty() {
        let slot = GeneralSectionSlot.slot
        #expect(slot.id == "general")
        #expect(slot.title == "General")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
