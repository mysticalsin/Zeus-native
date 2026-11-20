import Testing
import ZeusCore

@Suite struct LockScreenSectionSlotTests {
    @Test func lockScreenSitsOnTheFifthTopbarTab() {
        let slot = LockScreenSectionSlot.descriptor
        #expect(slot.id == "glass.lockScreen")
        #expect(slot.title == "Lock Screen")
        #expect(slot.placement == .topbarTab(5))
        #expect(slot.order == 5)
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.keys == LockScreenSettingKey.all)
        if case .cardOn = slot.placement {
            Issue.record("Lock Screen is a top bar tab")
        }
    }
}
