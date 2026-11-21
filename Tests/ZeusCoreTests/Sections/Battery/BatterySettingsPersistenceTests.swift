import Foundation
import Testing
import ZeusCore

@Suite("Battery settings persistence")
struct BatterySettingsPersistenceTests {
    @Test func eachBatterySettingSurvivesARecreatedStoreAndStartsOff() {
        let name = NSTemporaryDirectory() + "zeus.battery.persist.\(UUID().uuidString)"
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

    @Test func theSlotContributesBatterySettingsAndImportCannotEnableEarbuds() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let catalogIDs = catalog.split(separator: "\n").compactMap { line -> String? in
            guard line.contains("SettingOption(id:") else { return nil }
            return catalogLineID(String(line))
        }
        #expect(!catalogIDs.contains(BatteryEarbudSetting.key))
        #expect(!catalogIDs.contains(BatteryOverlayStyle.storageKey))
        let items = BatterySectionSlot.keyContributions
        #expect(SettingsKeyLedger.problems(catalogIDs: catalogIDs, contributions: items).isEmpty)
        let style = try #require(items.first { $0.id == BatteryOverlayStyle.storageKey })
        let earbuds = try #require(items.first { $0.id == BatteryEarbudSetting.key })
        #expect(style.kind == .choice)
        #expect(style.policy == .exportable)
        #expect(style.defaultValue == "gauge")
        #expect(earbuds.kind == .toggle)
        #expect(earbuds.policy == .importCannotEnable)
        #expect(earbuds.defaultValue == "false")
        #expect(SettingsKeyLedger.imported(earbuds, current: "false", incoming: "true") == nil)
        #expect(SettingsKeyLedger.imported(earbuds, current: "true", incoming: "false") == "false")
        #expect(SettingsDefaultsKey.key(BatteryEarbudSetting.key) == "opt.battery.earbuds")
        #expect(SettingsDefaultsKey.key(BatteryOverlayStyle.storageKey) == "opt.battery.overlayStyle")
    }

    private func catalogLineID(_ line: String) -> String? {
        guard let open = line.firstIndex(of: "\"") else { return nil }
        let rest = line[line.index(after: open)...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }
}
