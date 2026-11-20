import Testing
import ZeusCore

@Suite struct SensorySectionSlotTests {
    @Test func sensorySitsOnTopbarTabSeven() {
        let slot = SensorySectionSlot.descriptor
        #expect(slot.id == "glass.sensory")
        #expect(slot.title == "Sensory")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.placement == .topbarTab(7))
        #expect(slot.keys == [SensorySettings.holdKey, SensorySettings.labelKey])
        let tabs = GlassSectionManifest.topbarTabs()
        #expect(tabs.contains { $0.id == slot.id })
        #expect(tabs.first { $0.id == slot.id }?.placement == .topbarTab(7))
    }
}
