import Foundation
import Testing
@testable import ZeusCore

@Suite("Notification mirror preference")
struct NotificationMirrorPreferenceTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.notify-mirror.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aLegacyCatalogStringIsCopiedIntoTheBooleanAndKept() throws {
        let defaults = try fresh()
        defaults.set("true", forKey: NotificationMirrorPreference.legacyKey)
        #expect(NotificationMirrorPreference.isOn(defaults))
        #expect(defaults.object(forKey: NotificationMirrorPreference.key) == nil)
        #expect(NotificationMirrorPreference.migrate(defaults))
        #expect(defaults.object(forKey: NotificationMirrorPreference.key) as? Bool == true)
        #expect(defaults.string(forKey: NotificationMirrorPreference.legacyKey) == "true")
    }

    @Test func anExistingBooleanWinsAndTheLegacyStringStays() throws {
        let defaults = try fresh()
        defaults.set(false, forKey: NotificationMirrorPreference.key)
        defaults.set("true", forKey: NotificationMirrorPreference.legacyKey)
        #expect(!NotificationMirrorPreference.migrate(defaults))
        #expect(!NotificationMirrorPreference.isOn(defaults))
        #expect(defaults.string(forKey: NotificationMirrorPreference.legacyKey) == "true")
    }
}
