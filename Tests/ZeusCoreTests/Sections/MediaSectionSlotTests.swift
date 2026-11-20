import Testing
import ZeusCore

@Suite struct MediaSectionSlotTests {
    @Test func mediaSlotIsTheFirstTopbarTab() {
        let slot = MediaSectionSlot.descriptor
        #expect(slot.id == "glass.media")
        #expect(slot.title == "Media")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.order == 1)
        #expect(slot.placement == .topbarTab(1))
        #expect(slot.keys == MediaSettingID.added)
        let rows = SettingsSectionRegistry.sections(slots: GlassSectionManifest.slots)
        #expect(rows.last?.id == SettingsSectionRegistry.topbarID)
        #expect(!rows.contains { $0.id == slot.id })
        #expect(GlassSectionManifest.topbarTabs() == [slot])
        #expect(GlassSectionManifest.cards(on: .general).isEmpty)
        #expect(GlassSectionManifest.cards(on: .license).isEmpty)
        #expect(GlassSectionManifest.cards(on: .privacy).isEmpty)
        #expect(GlassSectionManifest.cards(on: .about).isEmpty)
    }
}
