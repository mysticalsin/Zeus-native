import Testing

@Suite struct BatterySectionSlotTests {
    @Test func batterySlotStartsEmpty() {
        let slot = BatterySectionSlot.slot
        #expect(slot.id == "glass.battery")
        #expect(slot.title == "Battery")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
