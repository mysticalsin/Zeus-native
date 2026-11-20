import Testing

@Suite struct FocusSectionSlotTests {
    @Test func focusSlotStartsEmpty() {
        let slot = FocusSectionSlot.slot
        #expect(slot.id == "focus")
        #expect(slot.title == "Focus")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
