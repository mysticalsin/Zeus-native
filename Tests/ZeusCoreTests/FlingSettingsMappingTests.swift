import Testing
@testable import ZeusCore

@Suite("Fling settings section mapping")
struct FlingSettingsMappingTests {
    /// REG-684: the debug open-settings call and the search find the Shelf section by name.
    @Test func theShelfSectionResolvesByNameInAnyCase() {
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("shelf") == "shelf")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("Shelf") == "shelf")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("  SHELF ") == "shelf")
    }
}
