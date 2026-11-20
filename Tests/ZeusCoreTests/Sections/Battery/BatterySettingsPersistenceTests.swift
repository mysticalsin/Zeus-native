import Foundation
import Testing
import ZeusCore

@Suite("Battery settings persistence")
struct BatterySettingsPersistenceTests {
    @Test func eachBatterySettingSurvivesARecreatedStoreAndStartsOff() {
        let name = "zeus.battery.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let fresh = BatterySettingsStore.load(defaults)
        #expect(fresh.earbudsEnabled == false)
        #expect(fresh.overlayStyle == .gauge)
        var edited = fresh
        edited.earbudsEnabled = true
        edited.overlayStyle = .ring
        edited.save(defaults)
        let again = BatterySettingsStore.load(UserDefaults(suiteName: name)!)
        #expect(again.earbudsEnabled)
        #expect(again.overlayStyle == .ring)
        #expect(again.styleRaw == "ring")
        #expect(again.earbudsRaw == "true")
        #expect(BatteryEarbudSetting.enabled(requested: true, origin: .importFile, currently: false) == false)
        #expect(BatteryEarbudSetting.enabled(requested: false, origin: .importFile, currently: true) == false)
    }

    @Test func theCatalogRegistersBatterySettingsAndImportCannotEnableEarbuds() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let store = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsStore.swift"), encoding: .utf8)
        let style = try #require(catalogLine("battery.overlayStyle", in: catalog))
        let earbuds = try #require(catalogLine("battery.earbuds", in: catalog))
        #expect(style.contains("kind: .choice"))
        #expect(style.contains("defaultValue: \"gauge\""))
        #expect(earbuds.contains("kind: .toggle"))
        #expect(earbuds.contains("defaultValue: \"false\""))
        #expect(store.contains("\"battery.earbuds\""))
        #expect(store.contains("SettingsDefaultsKey.key"))
        #expect(SettingsDefaultsKey.key(BatteryEarbudSetting.key) == "opt.battery.earbuds")
        #expect(SettingsDefaultsKey.key(BatteryOverlayStyle.storageKey) == "opt.battery.overlayStyle")
    }

    private func catalogLine(_ id: String, in source: String) -> String? {
        source.split(separator: "\n").first { $0.contains("SettingOption(id: \"\(id)\"") }.map(String.init)
    }
}
