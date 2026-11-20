import Testing
import ZeusCore

@Suite struct FocusSectionSlotTests {
    @Test func focusSlotPublishesTheOptInKeys() {
        let slot = FocusSectionSlot.descriptor
        #expect(slot.id == "glass.focus")
        #expect(slot.title == "Focus")
        #expect(slot.filled)
        #expect(slot.order == 4)
        #expect(slot.placement == .topbarTab(4))
        #expect(slot.keys == FocusSettingKey.optIn)
        #expect(!slot.keys.contains("home.widget.2"))
        #expect(!slot.keys.contains("notify.focus"))
    }
}
