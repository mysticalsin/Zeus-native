import Testing
import ZeusCore

@Suite struct SensorySectionSlotTests {
    @Test func sensorySitsOnTopbarTabSix() {
        let slot = SensorySectionSlot.descriptor
        #expect(slot.id == "glass.sensory")
        #expect(slot.title == "Sensory")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.order == 6)
        #expect(slot.placement == .topbarTab(6))
        #expect(slot.keys.isEmpty)
        let tabs = GlassSectionManifest.topbarTabs()
        #expect(tabs.contains { $0.id == slot.id })
        #expect(tabs.first { $0.id == slot.id }?.placement == .topbarTab(6))
    }
}
