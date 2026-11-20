import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Portal adds no setting key. The nearby-device controls are the existing `fling.*` catalog rows,
/// stored by `SettingsStore` as `opt.<id>`. `flingStartsOffAndAnImportNeverTurnsItOn` already pins the
/// import guard. This test sets every key, builds a new store on the same defaults, and reads them back.
@Suite("Portal settings persistence")
struct PortalSettingsPersistenceTests {
    private static let written: [String: String] = [
        "fling.enabled": "true",
        "fling.receiveInBackground": "false",
        "fling.deviceName": "Desk",
        "fling.visibility": "Paired only",
        "fling.autoAcceptPaired": "false",
        "fling.saveMode": "Clipboard",
        "fling.papers": "true",
        "fling.flickSensitivity": "High",
        "fling.openLinks": "false",
        "fling.pairedMacs": "alpha",
    ]

    @MainActor @Test func eachPortalKeySurvivesANewStoreOnTheSameDefaults() throws {
        let (first, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(Set(Self.written.keys) == Set(PortalDevices.existingKeys))
        #expect(SettingsCatalog.option("fling.enabled")?.defaultValue == "false")
        #expect(SettingsCatalog.option("fling.papers")?.defaultValue == "false")
        #expect(!first.bool("fling.enabled"))
        #expect(!first.bool("fling.papers"))
        for (id, value) in Self.written {
            let option = try #require(SettingsCatalog.option(id))
            #expect(option.section == .shelf)
            first.set(id, value)
        }
        let second = SettingsStore(defaults: defaults)
        for (id, value) in Self.written {
            #expect(second.string(id) == value)
            #expect(defaults.string(forKey: SettingsStore.key(id)) == value)
        }
        let board = PortalDeviceBoardBuilder.make(reading(second))
        #expect(board.canSend)
        #expect(board.canReceive)
    }

    @MainActor @Test func anImportCannotTurnFlingOrSyncOn() throws {
        let (store, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SettingsStore.neverEnabledByImport.contains("fling.enabled"))
        let file = try JSONSerialization.data(withJSONObject: [
            "format": "zeus.settings", "version": 1,
            "options": [
                "fling.enabled": "true",
                "fling.receiveInBackground": "false",
                "fling.deviceName": "Desk",
                "fling.visibility": "Paired only",
                "fling.autoAcceptPaired": "false",
                "fling.saveMode": "Clipboard",
                "fling.papers": "true",
                "fling.flickSensitivity": "High",
                "fling.openLinks": "false",
            ] as [String: String],
            "app": [String: String](),
        ])
        #expect(try store.importJSON(file) == 8)
        #expect(!store.bool("fling.enabled"))
        #expect(defaults.string(forKey: SettingsStore.key("fling.enabled")) == nil)
        #expect(store.string("fling.deviceName") == "Desk")
        #expect(store.string("fling.visibility") == "Paired only")
        let imported = SettingsStore(defaults: defaults)
        #expect(!imported.bool("fling.enabled"))
        #expect(imported.string("fling.flickSensitivity") == "High")
        let board = PortalDeviceBoardBuilder.make(reading(imported))
        #expect(board.phase == .off)
        #expect(!board.canSend)
        #expect(!board.canReceive)
        #expect(!board.opensLinks)
    }

    @MainActor private func store() throws -> (SettingsStore, UserDefaults, String) {
        let suite = NSTemporaryDirectory() + "zeus.portal.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (SettingsStore(defaults: defaults), defaults, suite)
    }

    @MainActor private func reading(_ store: SettingsStore) -> PortalFlingReading {
        PortalFlingReading(
            enabled: store.string("fling.enabled"),
            receiveInBackground: store.string("fling.receiveInBackground"),
            deviceName: store.string("fling.deviceName"),
            visibility: store.string("fling.visibility"),
            autoAcceptPaired: store.string("fling.autoAcceptPaired"),
            saveMode: store.string("fling.saveMode"),
            papers: store.string("fling.papers"),
            flickSensitivity: store.string("fling.flickSensitivity"),
            openLinks: store.string("fling.openLinks"),
            localNetworkDenied: false,
            peersKnown: true,
            notchOpen: true,
            paired: [],
            removal: .idle
        )
    }
}
