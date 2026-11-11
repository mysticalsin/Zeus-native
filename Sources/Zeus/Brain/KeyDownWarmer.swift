import Foundation
import ZeusCore

/// What the talk key warms the moment it goes down (never at launch): the TLS and HTTP/2 connection of the
/// brain that will answer, or the lean persistent `claude` process when there is no API key. Tony is still
/// speaking for a second or two, so the work is off the critical path. Repeated presses within a short
/// window do nothing, because an open connection or a running process is already warm.
enum KeyDownWarmer {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastWarm: [String: Date] = [:]
    static let httpWindow: TimeInterval = 45

    private static func due(_ name: String, window: TimeInterval) -> Bool {
        lock.withLock {
            let now = Date()
            if let last = lastWarm[name], now.timeIntervalSince(last) < window { return false }
            lastWarm[name] = now
            return true
        }
    }

    static func keys() -> VoiceTurnKeys {
        func hasKey(_ name: String) -> Bool { Keychain.get(name)?.isEmpty == false }
        func installed(_ tool: String) -> Bool {
            CLILocator.tools.first { $0.name == tool }.flatMap(CLILocator.locate) != nil
        }
        return VoiceTurnKeys(anthropicKey: hasKey("assistant.key.anthropic"), openAIKey: hasKey("assistant.key.openai"),
                             claudeCLI: installed("claude"), codexCLI: installed("codex"))
    }

    static func talkKeyDown() {
        Task.detached(priority: .userInitiated) {
            let keys = keys()
            for target in VoiceTurnRoute.brain(keys).warm {
                switch target {
                case .anthropicAPI:
                    if due("anthropic", window: httpWindow) { await AnthropicAPIProvider().prewarm() }
                case .openAIAPI:
                    if due("openai", window: httpWindow), let key = Keychain.get("assistant.key.openai"),
                       let model = ModelCap.httpModel(.openAI, tier: .fast) {
                        await OpenAICompatProvider.openAI(model: model, key: key).warmConnection()
                    }
                case .claudeCLI:
                    PersistentClaudeSession.shared.warm()
                }
            }
        }
    }
}
