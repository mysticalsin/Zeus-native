import Testing
import ZeusCore

@Suite struct AutoUpdateSectionSlotTests {
    @Test func autoUpdateSlotStartsEmpty() {
        let slot = AutoUpdateSectionSlot.descriptor
        #expect(slot.id == "glass.autoUpdate")
        #expect(slot.title == "Auto-update")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
