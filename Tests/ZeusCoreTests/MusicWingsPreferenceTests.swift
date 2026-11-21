import Foundation
import Testing
@testable import ZeusCore

@Suite("Music wings preference")
struct MusicWingsPreferenceTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.music-wings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aLegacyStringIsReadWhenTheBooleanIsAbsentAndTheReadDoesNotWrite() throws {
        let defaults = try fresh()
        defaults.set("false", forKey: MusicWingsPreference.legacyKey)
        #expect(MusicWingsPreference.isOn(defaults) == false)
        #expect(defaults.object(forKey: MusicWingsPreference.key) == nil)
        #expect(defaults.string(forKey: MusicWingsPreference.legacyKey) == "false")
    }

    @Test func migrateCopiesALegacyStringIntoTheBooleanAndKeepsTheString() throws {
        let defaults = try fresh()
        defaults.set("false", forKey: MusicWingsPreference.legacyKey)
        #expect(MusicWingsPreference.migrate(defaults))
        #expect(defaults.object(forKey: MusicWingsPreference.key) as? Bool == false)
        #expect(defaults.string(forKey: MusicWingsPreference.legacyKey) == "false")
        #expect(MusicWingsPreference.isOn(defaults) == false)
        #expect(!MusicWingsPreference.migrate(defaults))
    }

    @Test func anExistingBooleanWinsAndTheDisagreeingLegacyStringStays() throws {
        let defaults = try fresh()
        defaults.set(false, forKey: MusicWingsPreference.key)
        defaults.set("true", forKey: MusicWingsPreference.legacyKey)
        #expect(!MusicWingsPreference.migrate(defaults))
        #expect(defaults.object(forKey: MusicWingsPreference.key) as? Bool == false)
        #expect(defaults.string(forKey: MusicWingsPreference.legacyKey) == "true")
        #expect(MusicWingsPreference.isOn(defaults) == false)
    }

    @Test func settingWritesTheBooleanAndTheLegacyStringTogether() throws {
        let defaults = try fresh()
        MusicWingsPreference.set(false, defaults: defaults)
        #expect(defaults.object(forKey: MusicWingsPreference.key) as? Bool == false)
        #expect(defaults.string(forKey: MusicWingsPreference.legacyKey) == "false")
        MusicWingsPreference.set(true, defaults: defaults)
        #expect(defaults.object(forKey: MusicWingsPreference.key) as? Bool == true)
        #expect(defaults.string(forKey: MusicWingsPreference.legacyKey) == "true")
    }

    @Test func aMissingPairStaysMissingAndReadsOn() throws {
        let defaults = try fresh()
        #expect(MusicWingsPreference.isOn(defaults))
        #expect(!MusicWingsPreference.migrate(defaults))
        #expect(defaults.object(forKey: MusicWingsPreference.key) == nil)
        #expect(defaults.string(forKey: MusicWingsPreference.legacyKey) == nil)
    }
}
