import Testing
import ZeusCore

@Suite struct SettingsSectionRegistryTests {
    @Test func idsAreUnique() {
        let ids = SettingsSectionRegistry.existing.map(\.id) + GlassSectionManifest.slots.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func orderIsStable() {
        let slots = [GlassSectionSlot(id: "glass.synthetic", title: "Synthetic", filled: true, keys: [])]
        #expect(SettingsSectionRegistry.sections(slots: slots) == SettingsSectionRegistry.sections(slots: slots))
        #expect(SettingsSectionRegistry.existing.map(\.order) == Array(0..<SettingsSectionRegistry.existing.count))
    }

    @Test func existingOrderStaysFirst() {
        let before = SettingsSectionRegistry.existing.map(\.title)
        let slots = [GlassSectionSlot(id: "glass.synthetic", title: "Synthetic", filled: true, keys: [])]
        let after = SettingsSectionRegistry.sections(slots: slots)
        #expect(Array(after.prefix(before.count)).map(\.title) == before)
        #expect(before == ["General", "Appearance", "Sounds", "Notifications", "Shortcuts", "Insomnia", "Integrations", "Murmure", "Polyglot", "Dictation", "Voice", "Engine", "Features", "Beamer", "Tiling", "Shelf", "License", "Permissions", "Privacy", "Diagnostics", "About"])
    }

    @Test func aFilledSlotAppearsWithoutEditingTheRegistry() {
        let synthetic = GlassSectionSlot(id: "glass.synthetic", title: "Synthetic", filled: true, keys: [], placement: .topbarTab(0))
        #expect(!SettingsSectionRegistry.existing.contains { $0.id == SettingsSectionRegistry.topbarID })
        let rows = SettingsSectionRegistry.sections(slots: [synthetic])
        #expect(rows.last?.id == SettingsSectionRegistry.topbarID)
        #expect(rows.last?.accessibilityLabel == SettingsSectionRegistry.topbarTitle)
        #expect(!rows.contains { $0.id == synthetic.id })
    }

    @Test func aRegistrySectionIsTheSidebarAndTheAccessibilityRow() {
        let added = SettingsSectionDescriptor(
            id: "settings.fixture",
            title: "Fixture",
            order: SettingsSectionRegistry.existing.count,
            accessibilityLabel: "Fixture",
            placeholder: nil
        )
        let sections = SettingsSectionRegistry.sections(slots: []) + [added]
        let rows = GlassSettingsSidebar.rowIDs(sections: sections)
        let spoken = GlassSettingsAccessibility.exposure(sections: sections)
        #expect(rows.last == "settings.fixture")
        let last = spoken.last
        #expect(last?.label == "Fixture")
        #expect(last?.heading == true)
        #expect(last?.hidden == false)
    }

    @Test func searchStaysInRegistryOrder() {
        let found = SettingsSectionRegistry.search("u", in: SettingsSectionRegistry.existing)
        let indexes = found.compactMap { item in SettingsSectionRegistry.existing.firstIndex { $0.id == item.id } }
        #expect(indexes == indexes.sorted())
        #expect(found.first?.title == "Sounds")
        #expect(SettingsSectionRegistry.search("License", in: SettingsSectionRegistry.existing).first?.id == SettingsSectionRegistry.id(for: "license"))
    }
}
