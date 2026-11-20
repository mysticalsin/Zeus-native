import Foundation
import Testing
import ZeusCore

@Suite struct GeneralSectionSlotTests {
    @Test func generalCardsSitOnTheGeneralPage() {
        let slot = GeneralSectionSlot.descriptor
        #expect(slot.id == "glass.general")
        #expect(slot.title == "General")
        #expect(slot.filled == false)
        #expect(slot.enabled)
        #expect(slot.keys.isEmpty)
        #expect(slot.placement == .cardOn(.general, 1))
        #expect(GeneralSectionSlot.keyContributions == [
            GeneralSectionSlot.backgroundBlur,
            GeneralSectionSlot.hideInFullScreen,
            GeneralSectionSlot.hapticFeedback,
        ])
        #expect(GlassSectionManifest.cards(on: .general).isEmpty)
        #expect(GlassSectionManifest.cards(on: .license).contains { $0.id == "glass.general" } == false)
        #expect(GlassSectionManifest.topbarTabs().contains { $0.id == "glass.general" } == false)
    }

    @Test func contributedGeneralKeysRoundTripOutsideTheCatalog() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let items = GeneralSectionSlot.keyContributions
        #expect(SettingsKeyLedger.problems(catalogIDs: [], contributions: items).isEmpty)
        var stored: [String: String] = [:]
        for item in items {
            #expect(!catalog.contains("id: \"\(item.id)\""))
            #expect(SettingsKeyLedger.load(item, stored: nil) == item.defaultValue)
            let changed = item.kind == .toggle ? "true" : "55"
            #expect(SettingsKeyLedger.save(&stored, item, changed))
            #expect(SettingsKeyLedger.load(item, stored: stored[item.id]) == changed)
            #expect(SettingsKeyLedger.exportMap(stored: stored, contributions: [item])[item.id] == changed)
            #expect(SettingsKeyLedger.imported(item, current: item.defaultValue, incoming: changed) == changed)
            #expect(SettingsKeyLedger.resetValue(item) == item.defaultValue)
        }
        let again = stored
        for item in items {
            #expect(SettingsKeyLedger.load(item, stored: again[item.id]) == (item.kind == .toggle ? "true" : "55"))
        }
    }
}
