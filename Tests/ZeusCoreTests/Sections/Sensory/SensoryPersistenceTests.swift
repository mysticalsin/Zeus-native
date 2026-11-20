import Foundation
import Testing
@testable import ZeusCore

/// The hold and the label have to live in the shared catalog, under the same `opt.` keys the settings store already uses.
@Suite struct SensoryPersistenceTests {
    private static func repositoryRoot() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let catalog = url.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift")
            if FileManager.default.fileExists(atPath: catalog.path) { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    @Test func addedSensorySettingsAreCatalogRowsThatDefaultOff() throws {
        let root = try #require(Self.repositoryRoot())
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let hold = try optionLine(catalog, SensorySettings.holdKey)
        let label = try optionLine(catalog, SensorySettings.labelKey)
        #expect(hold.contains("defaultValue: \"1.2\""))
        #expect(label.contains("defaultValue: \"icon\""))
        #expect(!hold.contains("defaultValue: \"true\""))
        #expect(!label.contains("defaultValue: \"true\""))
        let fresh = SensorySettings.read { _ in nil }
        #expect(fresh.hold == 1.2)
        #expect(fresh.label == .icon)
        #expect(fresh.label != .words)
    }

    @Test func addedSensorySettingsSurviveTheSameStore() throws {
        let suite = "zeus.sensory.persist.\(UUID().uuidString)"
        let first = try #require(UserDefaults(suiteName: suite))
        defer { first.removePersistentDomain(forName: suite) }
        let written = SensorySettings(volume: false, brightness: true, replaceSystem: false, hold: 2.5, label: .words)
        written.write { first.set($1, forKey: "opt." + $0) }
        let second = try #require(UserDefaults(suiteName: suite))
        let read = SensorySettings.read { second.string(forKey: "opt." + $0) }
        #expect(read.hold == 2.5)
        #expect(read.label == .words)
        #expect(read.volume == false)
        #expect(read.brightness)
        #expect(read.replaceSystem == false)
        let freshName = suite + ".fresh"
        let freshDefaults = try #require(UserDefaults(suiteName: freshName))
        defer { freshDefaults.removePersistentDomain(forName: freshName) }
        let fresh = SensorySettings.read { freshDefaults.string(forKey: "opt." + $0) }
        #expect(fresh.hold == 1.2)
        #expect(fresh.label == .icon)
    }

    private func optionLine(_ catalog: String, _ id: String) throws -> String {
        let line = catalog.split(separator: "\n", omittingEmptySubsequences: false).first { $0.contains("id: \"\(id)\"") }
        return String(try #require(line))
    }
}
