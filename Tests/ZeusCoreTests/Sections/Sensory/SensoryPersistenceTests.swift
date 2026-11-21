import Foundation
import Testing
@testable import ZeusCore

/// Hold and label are section contributions. They are not catalog rows, and a fresh store stays off the words label.
@Suite struct SensoryPersistenceTests {
    @Test func addedSensorySettingsDefaultOffAndAreNotCatalogRows() throws {
        let items = SensorySectionSlot.keyContributions
        #expect(items.map(\.id) == [SensorySettings.holdKey, SensorySettings.labelKey])
        let hold = try #require(items.first { $0.id == SensorySettings.holdKey })
        let label = try #require(items.first { $0.id == SensorySettings.labelKey })
        #expect(hold.defaultValue == "1.2")
        #expect(hold.kind == .number)
        #expect(hold.policy == .exportable)
        #expect(SettingsKeyLedger.declaresPolicy(hold))
        #expect(label.defaultValue == "icon")
        #expect(label.kind == .choice)
        #expect(label.policy == .exportable)
        #expect(SettingsKeyLedger.declaresPolicy(label))
        #expect(hold.defaultValue != "true")
        #expect(label.defaultValue != "true")
        #expect(SettingsKeyLedger.load(hold, stored: nil) == "1.2")
        #expect(SettingsKeyLedger.load(label, stored: nil) == "icon")
        let root = try #require(repositoryRoot())
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let catalogIDs = SettingsKeyReachability.catalogIDs(in: catalog)
        #expect(!catalogIDs.contains(SensorySettings.holdKey))
        #expect(!catalogIDs.contains(SensorySettings.labelKey))
        #expect(SettingsKeyLedger.problems(catalogIDs: catalogIDs, contributions: GlassSectionManifest.keyContributions).isEmpty)
    }

    @Test func addedSensorySettingsSurviveTheSameStore() throws {
        let hold = try #require(SensorySectionSlot.keyContributions.first { $0.id == SensorySettings.holdKey })
        let label = try #require(SensorySectionSlot.keyContributions.first { $0.id == SensorySettings.labelKey })
        var stored: [String: String] = [:]
        #expect(SettingsKeyLedger.save(&stored, hold, "2.5"))
        #expect(SettingsKeyLedger.save(&stored, label, "words"))
        #expect(SettingsKeyLedger.load(hold, stored: stored[hold.id]) == "2.5")
        #expect(SettingsKeyLedger.load(label, stored: stored[label.id]) == "words")
        let exported = SettingsKeyLedger.exportMap(stored: stored, contributions: SensorySectionSlot.keyContributions)
        #expect(exported[hold.id] == "2.5")
        #expect(exported[label.id] == "words")
        let suite = NSTemporaryDirectory() + "zeus.sensory.persist.\(UUID().uuidString)"
        let first = try #require(UserDefaults(suiteName: suite))
        defer { first.removePersistentDomain(forName: suite) }
        for (id, value) in stored { first.set(value, forKey: "opt." + id) }
        let second = try #require(UserDefaults(suiteName: suite))
        let read = SensorySettings.read { second.string(forKey: "opt." + $0) }
        #expect(read.hold == 2.5)
        #expect(read.label == .words)
        let freshName = suite + ".fresh"
        let freshDefaults = try #require(UserDefaults(suiteName: freshName))
        defer { freshDefaults.removePersistentDomain(forName: freshName) }
        let fresh = SensorySettings.read { freshDefaults.string(forKey: "opt." + $0) }
        #expect(fresh.hold == 1.2)
        #expect(fresh.label == .icon)
    }

    private func repositoryRoot() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
