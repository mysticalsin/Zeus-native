import Testing
import ZeusCore

@Suite struct BatterySectionSlotTests {
    @Test func batteryIsTheThirdTopbarTab() {
        let slot = BatterySectionSlot.descriptor
        #expect(slot.id == "glass.battery")
        #expect(slot.title == "Battery")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.placement == .topbarTab(3))
        #expect(slot.keys == [BatteryOverlayStyle.storageKey, BatteryEarbudSetting.key])
        let rows = SettingsSectionRegistry.sections(slots: GlassSectionManifest.slots)
        #expect(!rows.contains { $0.id == slot.id })
        #expect(rows.contains { $0.id == SettingsSectionRegistry.topbarID })
        #expect(GlassSectionManifest.topbarTabs().contains { $0.id == slot.id })
    }
}
