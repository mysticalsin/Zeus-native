import Testing
import ZeusCore

@Suite struct WeatherSectionSlotTests {
    @Test func weatherIsTheSecondTopbarTab() {
        let slot = WeatherSectionSlot.descriptor
        #expect(slot.id == "glass.weather")
        #expect(slot.title == "Weather")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.keys.isEmpty)
        #expect(slot.placement == .topbarTab(1))
        #expect(slot.order == 1)
        #expect(GlassSectionManifest.topbarTabs().map(\.id) == ["glass.weather"])
        let rows = SettingsSectionRegistry.sections(slots: GlassSectionManifest.slots)
        #expect(!rows.contains { $0.id == "glass.weather" })
        #expect(rows.contains { $0.id == SettingsSectionRegistry.topbarID })
    }
}
