import Foundation
import Testing
@testable import ZeusCore

@Suite struct AIConnectionRegistryTests {
    private func isolatedDefaults() -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.ai-connections.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func preferenceText(_ defaults: UserDefaults) -> String {
        defaults.dictionaryRepresentation().map { key, value in
            let body: String
            if let data = value as? Data {
                body = String(data: data, encoding: .utf8) ?? String(describing: data)
            } else if let text = value as? String {
                body = text
            } else if let list = value as? [String] {
                body = list.joined(separator: "\n")
            } else {
                body = String(describing: value)
            }
            return key + "\n" + body
        }.joined(separator: "\n")
    }

    @Test func sectionListsTheSixConnectionKinds() {
        let rows = AIConnectionRegistry.standard().rows()
        #expect(rows.map(\.kind) == AIConnectionKind.allCases)
        #expect(rows.map { $0.kind.title } == [
            "Cloud Protocol", "CLI", "Cursor", "ElevenLabs API", "Other model APIs", "Voice chat",
        ])
        #expect(rows.map(\.kind.summary) == AIConnectionKind.allCases.map(\.summary))
        #expect(rows.map(\.id) == ["cloudProtocol", "cli", "cursor", "elevenLabsAPI", "modelAPI", "voiceChat"])
        let eleven = rows.first { $0.kind == .elevenLabsAPI }
        #expect(eleven?.plugs == [.elevenLabs])
        #expect(rows.filter { $0.kind != .elevenLabsAPI }.allSatisfy { $0.plugs.isEmpty })
    }

    @Test func elevenLabsStaysTheFirstExternalVoice() {
        var registry = AIConnectionRegistry.standard()
        #expect(registry.externalVoices.map(\.id) == ["elevenlabs.voice"])
        #expect(AIConnectionPlug.elevenLabs.keychainAccount == VoiceTTSProvider.elevenLabs.keychainAccount)
        #expect(VoiceProviderKeychain.accounts(for: .elevenLabs) == ["elevenlabs.api-key"])
        #expect(AIConnectionRegistry.diagnostic(saved: true) == VoiceProviderKeychain.logLine(present: true))
        #expect(AIConnectionRegistry.diagnostic(saved: false) == VoiceProviderKeychain.logLine(present: false))
        let later = AIConnectionPlug(id: "example.voice", title: "Example voice", kind: .voiceChat,
                                     keychainAccount: "example.voice-key", externalVoice: true)
        let cursor = AIConnectionPlug(id: "cursor.direct", title: "Cursor", kind: .cursor)
        #expect(registry.register(later) == .added)
        #expect(registry.register(cursor) == .added)
        #expect(registry.externalVoices.map(\.id) == ["elevenlabs.voice", "example.voice"])
        let store = KeychainStore(backend: MemoryKeychain(), defaults: isolatedDefaults())
        #expect(registry.status(for: .cursor, store: store) == AIConnectionStatus(label: "No key stored", saved: false, diagnostic: "key missing"))
        #expect(registry.status(for: .cloudProtocol, store: store).label == "No provider registered")
        #expect(registry.status(for: .elevenLabsAPI, store: store).label == "No key yet")
    }

    @Test func duplicateAndUnsafePlugsAreRejected() {
        var registry = AIConnectionRegistry.standard()
        let before = registry.plugs
        #expect(registry.register(.elevenLabs) == .duplicate)
        #expect(registry.register(AIConnectionPlug(id: "", title: "Nope", kind: .cli)) == .rejected)
        #expect(registry.register(AIConnectionPlug(id: "has space", title: "Nope", kind: .cli)) == .rejected)
        #expect(registry.register(AIConnectionPlug(id: "voice.example", title: "", kind: .voiceChat, externalVoice: true)) == .rejected)
        #expect(registry.register(AIConnectionPlug(id: "voice.example", title: "Example voice", kind: .voiceChat, externalVoice: true)) == .rejected)
        #expect(registry.register(AIConnectionPlug(id: "voice.example", title: "Example voice", kind: .voiceChat,
                                                   keychainAccount: "not a token", externalVoice: true)) == .rejected)
        #expect(registry.plugs == before)
    }

    @Test func syntheticSecretStaysInTheKeychainAndOutOfPreferences() throws {
        let secret = "synthetic-voice-secret"
        let defaults = isolatedDefaults()
        let backend = MemoryKeychain()
        let store = KeychainStore(backend: backend, defaults: defaults)
        var session = AIConnectionSession(defaults: defaults)
        session.setDraft(secret, plugID: "elevenlabs.voice")
        #expect(session.draft(for: "elevenlabs.voice") == secret)
        let beforeSave = try #require(session.preferencesData())
        #expect(!String(decoding: beforeSave, as: UTF8.self).contains(secret))
        #expect(!preferenceText(defaults).contains(secret))
        #expect(session.saveDraft(plugID: "elevenlabs.voice", store: store) == .saved)
        #expect(session.draft(for: "elevenlabs.voice").isEmpty)
        #expect(store.get("elevenlabs.api-key") == secret)
        #expect(backend.items == ["\(KeychainStore.service)|elevenlabs.api-key": secret])
        let saved = session.status(for: .elevenLabsAPI, store: store)
        #expect(saved == AIConnectionStatus(label: "Key saved", saved: true, diagnostic: "key present"))
        #expect(!saved.label.contains(secret) && !saved.diagnostic.contains(secret))
        let data = try #require(session.preferencesData())
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains(secret))
        let records = try JSONDecoder().decode([AIConnectionPreference].self, from: data)
        #expect(records == [AIConnectionPreference(plugID: "elevenlabs.voice", enabled: true, keychainAccount: "elevenlabs.api-key")])
        let objects = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(objects.allSatisfy { Set($0.keys) == Set(["enabled", "keychainAccount", "plugID"]) })
        #expect(!preferenceText(defaults).contains(secret))
        #expect(session.removeSecret(plugID: "elevenlabs.voice", store: store) == .removed)
        #expect(store.get("elevenlabs.api-key") == nil)
        #expect(backend.items.isEmpty)
        #expect(!preferenceText(defaults).contains(secret))
    }

    @Test func emptyDraftDoesNotRemoveASavedKey() {
        let secret = "synthetic-voice-secret"
        let defaults = isolatedDefaults()
        let backend = MemoryKeychain()
        let store = KeychainStore(backend: backend, defaults: defaults)
        var session = AIConnectionSession(defaults: defaults)
        session.setDraft(secret, plugID: "elevenlabs.voice")
        #expect(session.saveDraft(plugID: "elevenlabs.voice", store: store) == .saved)
        session.setDraft("   ", plugID: "elevenlabs.voice")
        #expect(session.saveDraft(plugID: "elevenlabs.voice", store: store) == .empty)
        #expect(store.get("elevenlabs.api-key") == secret)
        #expect(backend.items["\(KeychainStore.service)|elevenlabs.api-key"] == secret)
    }

    @Test func poisonedPreferencesAreReplacedAndNeverEnterTheKeychain() throws {
        let secret = "synthetic-voice-secret"
        let planted = Data("""
        [{"plugID":"elevenlabs.voice","enabled":true,"keychainAccount":"elevenlabs.api-key","apiKey":"\(secret)"}]
        """.utf8)
        let defaults = isolatedDefaults()
        defaults.set(planted, forKey: AIConnectionSession.preferencesKey)
        let backend = MemoryKeychain()
        let session = AIConnectionSession(defaults: defaults)
        let store = KeychainStore(backend: backend, defaults: defaults)
        _ = store.get("elevenlabs.api-key")
        let data = try #require(session.preferencesData())
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains(secret))
        let records = try JSONDecoder().decode([AIConnectionPreference].self, from: data)
        #expect(records == [AIConnectionPreference(plugID: "elevenlabs.voice", enabled: true, keychainAccount: "elevenlabs.api-key")])
        #expect(!text.contains("apiKey"))
        #expect(store.get("elevenlabs.api-key") == nil)
        #expect(!backend.items.values.contains(secret))
        #expect(!preferenceText(defaults).contains(secret))
        #expect(session.status(for: .elevenLabsAPI, store: store).label == "No key yet")

        let broken = isolatedDefaults()
        broken.set(Data("{\"apiKey\":\"\(secret)\"}".utf8), forKey: AIConnectionSession.preferencesKey)
        let brokenBackend = MemoryKeychain()
        let replaced = AIConnectionSession(defaults: broken)
        let brokenStore = KeychainStore(backend: brokenBackend, defaults: broken)
        _ = brokenStore.get(secret)
        let replacedText = String(decoding: try #require(replaced.preferencesData()), as: UTF8.self)
        #expect(!replacedText.contains(secret))
        #expect(!preferenceText(broken).contains(secret))
        #expect(brokenBackend.items.isEmpty)
    }

    @Test func refusedWriteLeavesTheDraftOutOfPreferences() {
        let secret = "synthetic-voice-secret"
        let defaults = isolatedDefaults()
        let store = KeychainStore(backend: RefusingKeychain(), defaults: defaults)
        var session = AIConnectionSession(defaults: defaults)
        session.setDraft(secret, plugID: "elevenlabs.voice")
        #expect(session.saveDraft(plugID: "elevenlabs.voice", store: store) == .refused)
        #expect(session.draft(for: "elevenlabs.voice") == secret)
        #expect(store.get("elevenlabs.api-key") == nil)
        #expect(!preferenceText(defaults).contains(secret))
        let text = String(decoding: session.preferencesData() ?? Data(), as: UTF8.self)
        #expect(!text.contains(secret))
        #expect(session.status(for: .elevenLabsAPI, store: store).diagnostic == "key missing")
    }

    @Test func registryFileDoesNotOpenTheNetwork() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ZeusCore/Connections/AIConnectionRegistry.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        for banned in ["URLSession", "URLRequest", "SecItem", "UserDefaults.standard", "print(", "NSLog", "os_log"] {
            #expect(!text.contains(banned))
        }
    }
}

private final class RefusingKeychain: KeychainBackend, @unchecked Sendable {
    func accounts(service: String) -> [String] { [] }
    func read(service: String, account: String) -> String? { nil }
    func write(_ value: String, service: String, account: String) -> Bool { false }
    func delete(service: String, account: String) -> Bool { false }
}
