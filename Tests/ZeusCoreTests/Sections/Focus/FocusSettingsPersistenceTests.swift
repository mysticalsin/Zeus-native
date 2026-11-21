import Foundation
import Testing
@testable import ZeusCore

@Suite struct FocusSettingsPersistenceTests {
    @Test func focusChoicesSurviveANewSessionFromTheSameStore() throws {
        let freshName = NSTemporaryDirectory() + "zeus.focus.fresh.\(UUID().uuidString)"
        let fresh = UserDefaults(suiteName: freshName)!
        fresh.removePersistentDomain(forName: freshName)
        let opened = FocusSectionSession(defaults: fresh)
        #expect(opened.settings.transitionOverlay == false)
        #expect(opened.settings.overlaysAllowed == false)
        #expect(opened.settings.lockScreen == false)
        #expect(opened.settings.readName == false)
        #expect(opened.settings.storeFile == false)
        #expect(opened.settings.localNetwork == false)
        #expect(opened.settings.sharedLink == false)
        for id in FocusSettingKey.optIn {
            #expect(FocusSettingsPersistence.storageKey(id) == "opt.\(id)")
            #expect(fresh.string(forKey: FocusSettingsPersistence.storageKey(id)) != "true")
        }

        let name = NSTemporaryDirectory() + "zeus.focus.kept.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        var session = FocusSectionSession(defaults: defaults)
        _ = session.handle(.setTransition(true))
        _ = session.handle(.setOverlaysAllowed(true))
        _ = session.handle(.setLockScreen(true))
        _ = session.handle(.setReadName(true))
        _ = session.handle(.setStoreFile(true))
        _ = session.handle(.setLocalNetwork(true))
        _ = session.handle(.setSharedLink(true))
        for id in FocusSettingKey.optIn {
            #expect(defaults.string(forKey: FocusSettingsPersistence.storageKey(id)) == "true")
        }

        let restored = FocusSectionSession(defaults: defaults)
        #expect(restored.settings.transitionOverlay)
        #expect(restored.settings.overlaysAllowed)
        #expect(restored.settings.lockScreen)
        #expect(restored.settings.readName)
        #expect(restored.settings.storeFile)
        #expect(restored.settings.localNetwork)
        #expect(restored.settings.sharedLink)

        let importedName = NSTemporaryDirectory() + "zeus.focus.import.\(UUID().uuidString)"
        let imported = UserDefaults(suiteName: importedName)!
        imported.removePersistentDomain(forName: importedName)
        var turnedOn: [String: String] = [:]
        for id in FocusSettingKey.optIn { turnedOn[id] = "true" }
        let file = try JSONSerialization.data(withJSONObject: [
            "format": "zeus.settings", "version": 1, "options": turnedOn,
        ])
        try FocusSettingsPersistence.importFile(file, into: imported)
        let afterImport = FocusSectionSession(defaults: imported)
        #expect(afterImport.settings.transitionOverlay == false)
        #expect(afterImport.settings.overlaysAllowed == false)
        #expect(afterImport.settings.lockScreen == false)
        #expect(afterImport.settings.readName == false)
        #expect(afterImport.settings.storeFile == false)
        #expect(afterImport.settings.localNetwork == false)
        #expect(afterImport.settings.sharedLink == false)
        for id in FocusSettingKey.sensitive {
            #expect(imported.string(forKey: FocusSettingsPersistence.storageKey(id)) != "true")
        }
    }
}
