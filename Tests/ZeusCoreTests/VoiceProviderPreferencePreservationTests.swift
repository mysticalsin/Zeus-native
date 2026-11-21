import Foundation
import Testing
@testable import ZeusCore

@Suite("Voice provider preference preservation")
struct VoiceProviderPreferencePreservationTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.voice-provider.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A raw value this card does not select, other than the local `kokoro` value.
    private func unsupportedRaw() throws -> String {
        let raw = VoiceTTSProvider.allCases.map(\.rawValue).first { value in
            VoiceProviderAccounts.choice(fromTTSProvider: value) == .local && value != VoiceTTSProvider.kokoro.rawValue
        }
        return try #require(raw)
    }

    @Test func readingDoesNotWriteAMissingKeyOrAnUnsupportedValue() throws {
        let missing = try fresh()
        _ = VoiceProviderPreferences(defaults: missing).choice
        #expect(missing.object(forKey: VoiceProviderPreferences.selectionKey) == nil)

        let defaults = try fresh()
        let raw = try unsupportedRaw()
        defaults.set(raw, forKey: VoiceProviderPreferences.selectionKey)
        _ = VoiceProviderPreferences(defaults: defaults).choice
        #expect(defaults.string(forKey: VoiceProviderPreferences.selectionKey) == raw)
    }

    @Test func assigningLocalOverwritesEveryCloudValueWithKokoro() throws {
        let clouds = VoiceTTSProvider.allCases.filter(\.needsKey)
        #expect(clouds.contains(.gemini))
        #expect(clouds.contains(.openAICompatible))
        #expect(!clouds.isEmpty)
        for provider in clouds {
            let defaults = try fresh()
            defaults.set(provider.rawValue, forKey: VoiceProviderPreferences.selectionKey)
            let prefs = VoiceProviderPreferences(defaults: defaults)
            prefs.choice = .local
            #expect(defaults.string(forKey: VoiceProviderPreferences.selectionKey) == VoiceTTSProvider.kokoro.rawValue,
                    "choosing local must overwrite \(provider.rawValue)")
        }
    }

    @Test func anUnknownStringMapsToTheLocalDefault() throws {
        let defaults = try fresh()
        defaults.set("future-engine", forKey: VoiceProviderPreferences.selectionKey)
        let prefs = VoiceProviderPreferences(defaults: defaults)
        #expect(prefs.choice == .local)
        #expect(defaults.string(forKey: VoiceProviderPreferences.selectionKey) == "future-engine")
        prefs.choice = .local
        #expect(defaults.string(forKey: VoiceProviderPreferences.selectionKey) == VoiceTTSProvider.kokoro.rawValue)
    }

    @Test func anExplicitLocalChoiceStillStoresKokoroWhenNothingElseIsStored() throws {
        let defaults = try fresh()
        VoiceProviderPreferences(defaults: defaults).choice = .local
        #expect(defaults.string(forKey: VoiceProviderPreferences.selectionKey) == VoiceTTSProvider.kokoro.rawValue)
    }

    @Test func aStoredCloudEngineDoesNotReadAsLocal() {
        for provider in [VoiceTTSProvider.gemini, .openAICompatible] {
            let choice = VoiceProviderAccounts.choice(fromTTSProvider: provider.rawValue)
            #expect(choice != .local)
            #expect(VoiceProviderAccounts.ttsProviderRaw(for: choice) == provider.rawValue)
        }
    }

    @Test func assigningLocalKeepsAnotherOnDeviceEngine() throws {
        let defaults = try fresh()
        let other = try #require(VoiceTTSProvider.allCases.first { !$0.needsKey && $0 != .kokoro })
        defaults.set(other.rawValue, forKey: VoiceProviderPreferences.selectionKey)
        VoiceProviderPreferences(defaults: defaults).choice = .local
        #expect(defaults.string(forKey: VoiceProviderPreferences.selectionKey) == other.rawValue)
    }

    @Test func theSettingsPickerUsesThePreferenceStore() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Voice/VoiceSettings.swift"), encoding: .utf8)
        #expect(source.contains("VoiceProviderPreferences"))
    }

    @Test func choosingAnAdapterReplacesThePreservedValue() throws {
        let defaults = try fresh()
        defaults.set(try unsupportedRaw(), forKey: VoiceProviderPreferences.selectionKey)
        let prefs = VoiceProviderPreferences(defaults: defaults)
        prefs.choice = .provider(ElevenLabsTTSAdapter.id)
        #expect(defaults.string(forKey: VoiceProviderPreferences.selectionKey) == VoiceTTSProvider.elevenLabs.rawValue)
    }
}
