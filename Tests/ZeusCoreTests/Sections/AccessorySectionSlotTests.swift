import Testing
import ZeusCore

@Suite struct AccessorySectionSlotTests {
    @Test func accessorySlotPublishesClosedKeys() {
        let slot = AccessorySectionSlot.descriptor
        #expect(slot.id == "glass.accessory")
        #expect(slot.title == "Accessory")
        #expect(slot.filled == true)
        #expect(slot.keys == [
            "accessory.earbudsOverlay",
            "accessory.overlayStyle",
            "accessory.speakerNames",
        ])
        #expect(slot.placement == .topbarTab(5))
    }
}
