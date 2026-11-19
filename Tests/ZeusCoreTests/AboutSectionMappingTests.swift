import Testing
@testable import ZeusCore

@Suite("About settings page mapping")
struct AboutSectionMappingTests {
    @Test func aboutResolvesToTheAboutPage() {
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("about") == "about")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("About") == "about")
        #expect(GlanceSettingsSnapshotMapping.glanceSectionID(forLegacySection: "about") == "about")
    }

    @Test func aboutYouStaysOnMemory() {
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("about you") == "features")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("memory") == "features")
    }
}
