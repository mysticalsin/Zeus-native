import Testing
import ZeusCore

@Suite struct SensorySectionSlotTests {
    @Test func sensorySlotStartsEmpty() {
        let slot = SensorySectionSlot.descriptor
        #expect(slot.id == "glass.sensory")
        #expect(slot.title == "Sensory")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
