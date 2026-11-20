import Testing
import ZeusCore

@Suite struct PortalSectionSlotTests {
    @Test func portalSectionAddsNoKey() {
        let slot = PortalSectionSlot.descriptor
        #expect(slot.id == "glass.portal")
        #expect(slot.title == "Portal")
        #expect(slot.filled == true)
        #expect(slot.keys.isEmpty)
        #expect(PortalSectionSlot.keyContributions.isEmpty)
        #expect(slot.order == 7)
        #expect(slot.placement == .topbarTab(7))
    }
}
