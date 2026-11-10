import Foundation
import IOKit
import Observation
import Security
import ZeusCore

/// The app's secrets, all under `com.zeus.app` through ZeusCore's `KeychainStore`: read once,
/// cached, never a password dialog. Snapshots never touch the Keychain.
enum Keychain {
    static let store: KeychainStore = KeychainStore(backend: TopBarStyle.isSnapshotSafe ? MemoryKeychain() : SystemKeychain())

    static func get(_ account: String) -> String? { store.get(account) }
    @discardableResult static func set(_ value: String, for account: String) -> Bool { store.set(value, for: account) }
    static func remove(_ account: String) { store.remove(account) }
}

extension TopBarStyle {
    /// Thread-agnostic read of the snapshot flag for Keychain calls.
    nonisolated static var isSnapshotSafe: Bool { ProcessInfo.processInfo.arguments.contains("--snapshots") }
}

/// Bring-your-own AI keys, one Keychain item each. The app only learns whether a key is saved.
@MainActor
@Observable
final class AssistantAccount {
    static let shared = AssistantAccount()

    enum Provider: String, CaseIterable, Identifiable {
        case openAI, anthropic, elevenLabs
        var id: String { rawValue }
        var title: String { switch self { case .openAI: "OpenAI"; case .anthropic: "Anthropic"; case .elevenLabs: "ElevenLabs" } }
        var account: String { "assistant.key.\(rawValue)" }
        var hint: String { switch self { case .openAI: "sk-…"; case .anthropic: "sk-ant-…"; case .elevenLabs: "xi-…" } }
        var use: String {
            switch self {
            case .openAI: "Chat and replies with GPT models."
            case .anthropic: "Chat and replies with Claude models."
            case .elevenLabs: "Natural voices for spoken answers."
            }
        }
        var models: [String] {
            switch self {
            // Haiku or Sonnet size at most (ModelCap): no Opus, no full-size GPT.
            case .openAI: ["gpt-5-mini", "gpt-4.1-mini"]
            case .anthropic: ["claude-haiku-4-5", "claude-sonnet-4-5"]
            case .elevenLabs: ["eleven_multilingual_v2", "eleven_flash_v2_5"]
            }
        }
    }

    private(set) var saved: Set<Provider> = []

    init() { refresh() }

    var isSignedIn: Bool { !saved.isEmpty }

    func refresh() {
        guard !TopBarStyle.isSnapshot else { return }
        saved = Set(Provider.allCases.filter { Keychain.get($0.account) != nil })
    }

    func save(_ key: String, for provider: Provider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Keychain.set(trimmed, for: provider.account) else { return }
        saved.insert(provider)
    }

    func remove(_ provider: Provider) {
        Keychain.remove(provider.account)
        saved.remove(provider)
    }

    func signOut() { Provider.allCases.forEach(remove) }

    /// For whichever feature talks to the provider (chat, replies). Never logged.
    func key(for provider: Provider) -> String? { Keychain.get(provider.account) }

    func setSavedForSnapshot(_ providers: Set<Provider>) { saved = providers }
}
