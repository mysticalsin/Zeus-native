import Foundation
import Testing
@testable import ZeusCore

@Suite("Persisted voice settings load")
struct PersistedVoiceSettingsLoadTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.persisted-voice.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aStringBooleanDoesNotDropTheSavedEngine() throws {
        let json = Data("""
        {"voice.engine":"kokoro","voice.engine.userSelected":"true","voice.ttsProvider":"kokoro"}
        """.utf8)
        let saved = try JSONDecoder().decode(PersistedVoiceSettings.self, from: json)
        #expect(saved.engine == "kokoro")
        #expect(saved.userSelected)
        #expect(saved.ttsProvider == "kokoro")
    }

    @Test func userDefaultsKeysLoadWithoutASecondStore() throws {
        let defaults = try fresh()
        defaults.set("system", forKey: "voice.engine")
        defaults.set(true, forKey: "voice.engine.userSelected")
        defaults.set("kokoro", forKey: "voice.ttsProvider")
        defaults.set(false, forKey: "voice.engine.auto")
        let saved = PersistedVoiceSettings.load(defaults)
        #expect(saved.engine == "system")
        #expect(saved.userSelected)
        #expect(saved.ttsProvider == "kokoro")
        #expect(saved.engineAuto == false)
    }
}
