import Testing

@Suite struct AccessorySectionSlotTests {
    @Test func accessorySlotStartsEmpty() {
        let slot = AccessorySectionSlot.slot
        #expect(slot.id == "accessory")
        #expect(slot.title == "Accessory")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
