import Testing
import ZeusCore

@Suite struct LicenseSectionSlotTests {
    @Test func licenseCardSitsOnTheLicensePage() {
        let slot = LicenseSectionSlot.descriptor
        #expect(slot.id == "glass.license")
        #expect(slot.title == "License")
        #expect(slot.filled == true)
        #expect(slot.enabled == true)
        #expect(slot.keys.isEmpty)
        #expect(slot.order == 1)
        #expect(slot.placement == .cardOn(.license, 1))
        let hosted = GlassSectionManifest.cards(on: .license)
        #expect(hosted.map(\.id) == ["glass.license"])
        #expect(hosted.first?.placement == .cardOn(.license, 1))
        #expect(LicenseSectionSlot.keyContributions.map(\.id) == ["license.activationState", "license.lastValidated"])
        #expect(LicenseSectionSlot.keyContributions.allSatisfy { $0.policy == .localOnly })
        #expect(!LicenseSectionSlot.keyContributions.contains { $0.id == "license.key" })
    }
}