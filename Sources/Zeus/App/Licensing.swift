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
    @discardableResult static func remove(_ account: String) -> Bool { store.remove(account) }
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
    private(set) var keyMessage: String?

    init() { refresh() }

    var isSignedIn: Bool { !saved.isEmpty }

    func refresh() {
        guard !TopBarStyle.isSnapshot else { return }
        saved = Set(Provider.allCases.filter { Keychain.get($0.account) != nil })
    }

    @discardableResult
    func save(_ key: String, for provider: Provider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard Keychain.set(trimmed, for: provider.account) else {
            keyMessage = "Couldn't save the \(provider.title) key. Check Keychain access and try again."
            return false
        }
        saved.insert(provider)
        keyMessage = nil
        return true
    }

    @discardableResult
    func remove(_ provider: Provider) -> Bool {
        guard Keychain.remove(provider.account) else {
            keyMessage = "Couldn't remove the \(provider.title) key. Check Keychain access and try again."
            return false
        }
        saved.remove(provider)
        keyMessage = nil
        return true
    }

    func signOut() {
        let failed = Provider.allCases.filter { !remove($0) }
        if !failed.isEmpty {
            keyMessage = "Couldn't remove \(failed.map(\.title).joined(separator: ", ")) keys. Check Keychain access and try again."
        }
    }

    /// For whichever feature talks to the provider (chat, replies). Never logged.
    func key(for provider: Provider) -> String? { Keychain.get(provider.account) }

    func setSavedForSnapshot(_ providers: Set<Provider>) { saved = providers }
}
