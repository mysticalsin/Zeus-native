import Testing
import ZeusCore

@Suite struct FocusSectionSlotTests {
    @Test func focusSlotUsesTheShellPlacement() {
        let slot = FocusSectionSlot.descriptor
        #expect(slot.id == "glass.focus")
        #expect(slot.title == "Focus")
        #expect(slot.filled)
        #expect(slot.order == 3)
        #expect(slot.placement == .topbarTab(3))
        #expect(slot.keys.isEmpty)
    }
}
