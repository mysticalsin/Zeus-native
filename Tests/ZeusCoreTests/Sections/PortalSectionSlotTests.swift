import Testing

@Suite struct PortalSectionSlotTests {
    @Test func portalSlotStartsEmpty() {
        let slot = PortalSectionSlot.descriptor
        #expect(slot.id == "glass.portal")
        #expect(slot.title == "Portal")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
