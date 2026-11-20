import Testing
@testable import ZeusCore

@Suite struct MediaSectionSlotTests {
    @Test func mediaSlotPublishesThePlayerSection() {
        let slot = MediaSectionSlot.descriptor
        #expect(slot.id == "glass.media")
        #expect(slot.title == "Media")
        #expect(slot.filled)
        #expect(slot.order == 100)
        #expect(slot.keys == MediaSettingID.added)
        #expect(MediaSectionPlacement.topbarTab == 1)
    }
}
