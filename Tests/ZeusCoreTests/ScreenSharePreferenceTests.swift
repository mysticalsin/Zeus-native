import Foundation
import Testing
@testable import ZeusCore

@Suite("Screen share preference")
struct ScreenSharePreferenceTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.screen-share.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theLiveStringWinsOverAMissingBoolean() throws {
        let defaults = try fresh()
        defaults.set("true", forKey: ZeusScreenSharePolicy.storedKey)
        #expect(ZeusScreenSharePolicy.showInScreenSharing(from: defaults))
    }

    @Test func anExplicitHideKeyStillMeansHiddenWhenTheLiveStringIsAbsent() throws {
        let defaults = try fresh()
        defaults.set(true, forKey: ZeusScreenSharePolicy.legacyHideKey)
        #expect(!ZeusScreenSharePolicy.showInScreenSharing(from: defaults))
        #expect(ZeusScreenSharePolicy.migrate(defaults))
        #expect(defaults.string(forKey: ZeusScreenSharePolicy.storedKey) == "false")
        #expect(defaults.object(forKey: ZeusScreenSharePolicy.legacyHideKey) as? Bool == true)
    }

    @Test func migrateDoesNotInventAChoiceOrOverwriteTheLiveString() throws {
        let empty = try fresh()
        #expect(!ZeusScreenSharePolicy.migrate(empty))
        #expect(empty.string(forKey: ZeusScreenSharePolicy.storedKey) == nil)
        #expect(!ZeusScreenSharePolicy.showInScreenSharing(from: empty))

        let defaults = try fresh()
        defaults.set("true", forKey: ZeusScreenSharePolicy.storedKey)
        defaults.set(true, forKey: ZeusScreenSharePolicy.legacyHideKey)
        #expect(!ZeusScreenSharePolicy.migrate(defaults))
        #expect(defaults.string(forKey: ZeusScreenSharePolicy.storedKey) == "true")
        #expect(defaults.object(forKey: ZeusScreenSharePolicy.legacyHideKey) as? Bool == true)
        #expect(ZeusScreenSharePolicy.showInScreenSharing(from: defaults))
    }
}
