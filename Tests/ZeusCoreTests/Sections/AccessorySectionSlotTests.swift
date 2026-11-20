import Testing

@Suite struct AccessorySectionSlotTests {
    @Test func accessorySlotStartsEmpty() {
        let slot = AccessorySectionSlot.descriptor
        #expect(slot.id == "glass.accessory")
        #expect(slot.title == "Accessory")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
