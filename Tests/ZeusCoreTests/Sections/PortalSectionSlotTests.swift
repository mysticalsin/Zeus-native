import Testing

@Suite struct PortalSectionSlotTests {
    @Test func portalSectionAddsNoKey() {
        let slot = PortalSectionSlot.descriptor
        #expect(slot.id == "glass.portal")
        #expect(slot.title == "Portal")
        #expect(slot.filled == true)
        #expect(slot.keys.isEmpty)
        #expect(slot.order == 120)
    }
}
