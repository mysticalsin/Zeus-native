import Testing
import ZeusCore

@Suite struct AutoUpdateSectionSlotTests {
    @Test func autoUpdateCardSitsOnAbout() {
        let slot = AutoUpdateSectionSlot.descriptor
        #expect(slot.id == "glass.autoUpdate")
        #expect(slot.title == "Auto-update")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.keys.isEmpty)
        #expect(slot.placement == .cardOn(.about, 1))
        #expect(GlassSectionManifest.cards(on: .about).map(\.id) == ["glass.autoUpdate"])
        #expect(AutoUpdateSectionSlot.cardTitle == "Updates")
    }
}
