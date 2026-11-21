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

    /// Resetting the legacy hide key withdraws a stored "show". The live string is false afterwards.
    @Test func resetOfInterviewHideLeavesTheLiveStringFalse() throws {
        let defaults = try fresh()
        defaults.set("true", forKey: ZeusScreenSharePolicy.storedKey)
        defaults.set(false, forKey: ZeusScreenSharePolicy.legacyHideKey)
        ZeusScreenSharePolicy.reset(["interview.hide"], defaults: defaults)
        #expect(defaults.string(forKey: "opt.general.showInScreenSharing") == "false")
        #expect(!ZeusScreenSharePolicy.showInScreenSharing(from: defaults))
    }

    /// Import, agent, migration, and reset may hide Zeus. Only a person may turn showing on.
    @Test func onlyAPersonCanEnableShowing() {
        #expect(ZeusScreenSharePolicy.persistsShow(requestedTrue: true, origin: .person))
        for origin in [ZeusScreenSharePolicy.WriteOrigin.reset, .importFile, .agent, .migration] {
            #expect(!ZeusScreenSharePolicy.persistsShow(requestedTrue: true, origin: origin), "\(origin) must not enable showing")
            #expect(ZeusScreenSharePolicy.persistsShow(requestedTrue: false, origin: origin), "\(origin) may downgrade to hidden")
        }
    }

    /// A migration copies a hidden legacy choice and never writes the live string as "true".
    @Test func migrationDoesNotEnableShowing() throws {
        let shownByHideFlag = try fresh()
        shownByHideFlag.set(false, forKey: ZeusScreenSharePolicy.legacyHideKey)
        _ = ZeusScreenSharePolicy.migrate(shownByHideFlag)
        #expect(shownByHideFlag.string(forKey: ZeusScreenSharePolicy.storedKey) != "true")

        let shownByBoolean = try fresh()
        shownByBoolean.set(true, forKey: ZeusScreenSharePolicy.showInSharingKey)
        _ = ZeusScreenSharePolicy.migrate(shownByBoolean)
        #expect(shownByBoolean.string(forKey: ZeusScreenSharePolicy.storedKey) != "true")
    }
}
