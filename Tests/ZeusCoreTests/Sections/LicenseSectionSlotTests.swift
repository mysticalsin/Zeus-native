import Testing

@Suite struct LicenseSectionSlotTests {
    @Test func licenseSlotStartsEmpty() {
        let slot = LicenseSectionSlot.slot
        #expect(slot.id == "glass.license")
        #expect(slot.title == "License")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
