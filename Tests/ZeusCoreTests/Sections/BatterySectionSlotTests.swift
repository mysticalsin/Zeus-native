import Testing
import ZeusCore

@Suite struct BatterySectionSlotTests {
    @Test func batteryIsTheThirdTopbarTab() {
        let slot = BatterySectionSlot.descriptor
        #expect(slot.id == "glass.battery")
        #expect(slot.title == "Battery")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.placement == .topbarTab(2))
        #expect(slot.order == 2)
        #expect(slot.keys.isEmpty)
        let rows = SettingsSectionRegistry.sections(slots: GlassSectionManifest.slots)
        #expect(!rows.contains { $0.id == slot.id })
        #expect(rows.contains { $0.id == SettingsSectionRegistry.topbarID })
        #expect(GlassSectionManifest.topbarTabs().contains { $0.id == slot.id })
    }
}
