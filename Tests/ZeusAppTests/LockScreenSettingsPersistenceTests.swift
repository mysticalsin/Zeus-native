import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Lock screen values go through SettingsStore. A new store on the same defaults reads them back.
@Suite("Lock screen settings persistence")
struct LockScreenSettingsPersistenceTests {
    private func isolated() throws -> (UserDefaults, cleanup: () -> Void) {
        let name = NSTemporaryDirectory() + "zeus.lockscreen.store.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    private func file(_ options: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "format": "zeus.settings", "version": 1, "options": options, "app": [String: String](),
        ])
    }

    @MainActor @Test func eachLockScreenKeySurvivesANewStoreOnTheSameDefaults() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        let fresh = SettingsStore(defaults: defaults)
        for item in LockScreenSectionSlot.keyContributions {
            #expect(item.policy == .importCannotEnable)
            #expect(item.defaultValue == "false" || item.defaultValue == "Off")
            #expect(fresh.string(item.id) == item.defaultValue)
        }
        let first = SettingsStore(defaults: defaults)
        let saved = [
            LockScreenSettingKey.playerCard: "true",
            LockScreenSettingKey.lockSound: "Gentle",
            LockScreenSettingKey.unlockSound: "To-do",
            LockScreenSettingKey.soundLevel: "Quiet",
        ]
        for (id, value) in saved {
            first.set(id, value)
        }
        let second = SettingsStore(defaults: defaults)
        for (id, value) in saved {
            #expect(second.string(id) == value)
        }
    }

    @MainActor @Test func anImportCannotEnableLockScreenSettings() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        let store = SettingsStore(defaults: defaults)
        let changed = try store.importJSON(file([
            LockScreenSettingKey.playerCard: "true",
            LockScreenSettingKey.lockSound: "Gentle",
            LockScreenSettingKey.unlockSound: "Listening",
            LockScreenSettingKey.soundLevel: "Loud",
        ]))
        #expect(changed == 0)
        #expect(store.string(LockScreenSettingKey.playerCard) == "false")
        #expect(store.string(LockScreenSettingKey.lockSound) == "Off")
        #expect(store.string(LockScreenSettingKey.unlockSound) == "Off")
        #expect(store.string(LockScreenSettingKey.soundLevel) == "Off")
        for id in LockScreenSettingKey.all {
            #expect(defaults.string(forKey: SettingsStore.key(id)) == nil)
        }
    }
}
