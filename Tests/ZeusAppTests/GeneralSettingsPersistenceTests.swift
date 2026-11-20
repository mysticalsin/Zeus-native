import Foundation
import Testing
@testable import Zeus

@Suite("General settings persistence")
struct GeneralSettingsPersistenceTests {
    private static let added = [
        "general.backgroundBlur": "55",
        "general.hideInFullScreen": "true",
        "general.hapticFeedback": "true",
    ]

    @MainActor @Test func addedKeysSurviveANewStoreAndStayInSearchImportAndReset() throws {
        let suiteName = NSTemporaryDirectory() + "zeus.general.persist.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        for (key, value) in Self.added { first.set(key, value) }
        first.set("general.windowTheme", "Light")

        let second = SettingsStore(defaults: defaults)
        for (key, value) in Self.added {
            #expect(second.string(key) == value)
            let option = try #require(SettingsCatalog.option(key))
            #expect(option.isShown)
            #expect(option.state == .live)
            #expect(SettingsCatalog.search(option.title).contains { $0.id == key })
        }
        #expect(second.string("general.windowTheme") == "Light")

        let exported = try JSONSerialization.jsonObject(with: first.exportJSON()) as? [String: Any]
        let options = try #require(exported?["options"] as? [String: String])
        for (key, value) in Self.added { #expect(options[key] == value) }

        let freshName = NSTemporaryDirectory() + "zeus.general.import.\(UUID().uuidString)"
        let freshDefaults = try #require(UserDefaults(suiteName: freshName))
        defer { freshDefaults.removePersistentDomain(forName: freshName) }
        let fresh = SettingsStore(defaults: freshDefaults)
        let imported = try fresh.importJSON(first.exportJSON())
        #expect(imported == Self.added.count)
        for (key, value) in Self.added { #expect(fresh.string(key) == value) }

        fresh.reset(.general)
        #expect(fresh.string("general.backgroundBlur") == "40")
        #expect(fresh.string("general.hideInFullScreen") == "false")
        #expect(fresh.string("general.hapticFeedback") == "false")
    }
}
