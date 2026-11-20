import Testing
import ZeusCore

@Suite struct LicenseSectionSlotTests {
    @Test func licenseSlotStartsEmpty() {
        let slot = LicenseSectionSlot.descriptor
        #expect(slot.id == "glass.license")
        #expect(slot.title == "License")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
