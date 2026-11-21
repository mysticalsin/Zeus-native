import Testing
import ZeusCore

@Suite struct FocusSectionSlotTests {
    @Test func focusSlotStartsEmpty() {
        let slot = FocusSectionSlot.descriptor
        #expect(slot.id == "glass.focus")
        #expect(slot.title == "Focus")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
