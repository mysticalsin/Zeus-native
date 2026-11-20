import Testing

@Suite struct PortalSectionSlotTests {
    @Test func portalSlotStartsEmpty() {
        let slot = PortalSectionSlot.slot
        #expect(slot.id == "portal")
        #expect(slot.title == "Portal")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
