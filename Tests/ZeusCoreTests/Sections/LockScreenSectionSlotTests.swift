import Testing

@Suite struct LockScreenSectionSlotTests {
    @Test func lockScreenSlotStartsEmpty() {
        let slot = LockScreenSectionSlot.slot
        #expect(slot.id == "glass.lockScreen")
        #expect(slot.title == "Lock Screen")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
