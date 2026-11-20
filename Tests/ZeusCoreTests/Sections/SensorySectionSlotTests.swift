import Testing

@Suite struct SensorySectionSlotTests {
    @Test func sensorySlotStartsEmpty() {
        let slot = SensorySectionSlot.slot
        #expect(slot.id == "sensory")
        #expect(slot.title == "Sensory")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
