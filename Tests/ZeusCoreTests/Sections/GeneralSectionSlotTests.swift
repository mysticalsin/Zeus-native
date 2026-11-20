import Foundation
import Testing
import ZeusCore

@Suite struct GeneralSectionSlotTests {
    @Test func generalCardsSitOnTheGeneralPage() {
        let slot = GeneralSectionSlot.descriptor
        #expect(slot.id == "glass.general")
        #expect(slot.title == "General")
        #expect(slot.filled)
        #expect(slot.enabled)
        #expect(slot.placement == .cardOn(.general, 1))
        #expect(slot.keys.sorted() == ["general.backgroundBlur", "general.hapticFeedback", "general.hideInFullScreen"])
        #expect(GlassSectionManifest.cards(on: .general).map(\.id) == ["glass.general"])
        #expect(GlassSectionManifest.cards(on: .license).contains { $0.id == "glass.general" } == false)
        #expect(GlassSectionManifest.topbarTabs().contains { $0.id == "glass.general" } == false)
    }

    @Test func addedGeneralSettingsAreLiveCatalogRows() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let lines = catalog.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func row(_ id: String) throws -> String {
            try #require(lines.first { $0.contains("id: \"\(id)\"") })
        }
        let blur = try row("general.backgroundBlur")
        #expect(blur.contains("kind: .slider"))
        #expect(blur.contains("defaultValue: \"40\""))
        #expect(blur.contains("state: .live"))
        #expect(blur.contains("Range(min: 0, max: 100, step: 1)"))
        let fullScreen = try row("general.hideInFullScreen")
        #expect(fullScreen.contains("kind: .toggle"))
        #expect(fullScreen.contains("defaultValue: \"false\""))
        #expect(fullScreen.contains("state: .live"))
        let haptic = try row("general.hapticFeedback")
        #expect(haptic.contains("kind: .toggle"))
        #expect(haptic.contains("defaultValue: \"false\""))
        #expect(haptic.contains("state: .live"))
    }
}
