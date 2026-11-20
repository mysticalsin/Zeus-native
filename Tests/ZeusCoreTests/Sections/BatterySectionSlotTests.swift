import Testing

@Suite struct BatterySectionSlotTests {
    @Test func batterySlotStartsEmpty() {
        let slot = BatterySectionSlot.descriptor
        #expect(slot.id == "glass.battery")
        #expect(slot.title == "Battery")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
