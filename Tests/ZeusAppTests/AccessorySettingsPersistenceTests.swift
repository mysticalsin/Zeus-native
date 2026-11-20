import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Accessory settings persistence")
struct AccessorySettingsPersistenceTests {
    /// Sets each accessory key, builds a new store on the same defaults, and checks the value survived.
    /// A fresh store stays off. An import cannot turn the connect switch, the overlay style, or speaker names on.
    @MainActor @Test func accessorySettingsSurviveANewStoreAndAnImportCannotTurnThemOn() throws {
        let (fresh, defaults, suite) = try Self.isolated()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(fresh.bool(AccessoryPreferenceKey.earbudsOverlay) == false)
        #expect(fresh.string(AccessoryPreferenceKey.overlayStyle) == AccessoryOverlayStyle.off.rawValue)
        #expect(fresh.bool(AccessoryPreferenceKey.speakerNames) == false)
        #expect(SettingsCatalog.option(AccessoryPreferenceKey.earbudsOverlay) == nil)
        #expect(SettingsStore.contribution(AccessoryPreferenceKey.earbudsOverlay)?.policy == .importCannotEnable)
        #expect(SettingsStore.contribution(AccessoryPreferenceKey.overlayStyle)?.policy == .importCannotEnable)
        #expect(SettingsStore.contribution(AccessoryPreferenceKey.speakerNames)?.policy == .importCannotEnable)
        #expect(SettingsCatalog.search("speaker").contains { $0.id == AccessoryPreferenceKey.speakerNames })

        fresh.set(AccessoryPreferenceKey.earbudsOverlay, "true")
        fresh.set(AccessoryPreferenceKey.overlayStyle, "split")
        fresh.set(AccessoryPreferenceKey.speakerNames, "true")
        let again = SettingsStore(defaults: defaults)
        #expect(again.bool(AccessoryPreferenceKey.earbudsOverlay))
        #expect(again.string(AccessoryPreferenceKey.overlayStyle) == "split")
        #expect(again.bool(AccessoryPreferenceKey.speakerNames))

        let exported = try again.exportJSON()
        let root = try #require(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let options = try #require(root["options"] as? [String: String])
        #expect(options[AccessoryPreferenceKey.earbudsOverlay] == "true")
        #expect(options[AccessoryPreferenceKey.overlayStyle] == "split")
        #expect(options[AccessoryPreferenceKey.speakerNames] == "true")

        let (imported, importDefaults, importSuite) = try Self.isolated()
        defer { importDefaults.removePersistentDomain(forName: importSuite) }
        _ = try imported.importJSON(exported)
        #expect(imported.bool(AccessoryPreferenceKey.earbudsOverlay) == false)
        #expect(imported.string(AccessoryPreferenceKey.overlayStyle) == AccessoryOverlayStyle.off.rawValue)
        #expect(imported.bool(AccessoryPreferenceKey.speakerNames) == false)
    }

    @MainActor private static func isolated() throws -> (SettingsStore, UserDefaults, String) {
        let suite = "zeus.accessory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (SettingsStore(defaults: defaults), defaults, suite)
    }
}
