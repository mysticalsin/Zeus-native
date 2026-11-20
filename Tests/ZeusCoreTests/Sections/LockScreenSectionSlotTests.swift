import Testing
import ZeusCore

@Suite struct LockScreenSectionSlotTests {
    @Test func lockScreenUsesTheShellTopbarPlacement() {
        let slot = LockScreenSectionSlot.descriptor
        #expect(slot.id == "glass.lockScreen")
        #expect(slot.title == "Lock Screen")
        #expect(slot.placement == .topbarTab(4))
        #expect(slot.order == 4)
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.keys.isEmpty)
    }
}
