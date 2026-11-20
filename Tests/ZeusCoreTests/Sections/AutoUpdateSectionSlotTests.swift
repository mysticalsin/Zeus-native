import Testing

@Suite struct AutoUpdateSectionSlotTests {
    @Test func autoUpdateSlotStartsEmpty() {
        let slot = AutoUpdateSectionSlot.slot
        #expect(slot.id == "autoUpdate")
        #expect(slot.title == "Auto-update")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
