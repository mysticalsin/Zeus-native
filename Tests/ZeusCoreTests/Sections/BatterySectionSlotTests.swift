import Testing
import ZeusCore

@Suite struct BatterySectionSlotTests {
    @Test func batterySlotIsFilledForTheGlassHost() {
        let slot = BatterySectionSlot.descriptor
        #expect(slot.id == "glass.battery")
        #expect(slot.title == "Battery")
        #expect(slot.filled)
        #expect(slot.keys == [BatteryOverlayStyle.storageKey, BatteryEarbudSetting.key])
        #expect(slot.order == 140)
        #expect(BatterySectionPlacement.topbarTab == 3)
    }
}
