import AppKit
import Observation
import SwiftUI
import ZeusCore

/// Where each AI stands on this Mac, and the actions behind Connect and Check again.
@MainActor
@Observable
final class AIConnections {
    static let shared = AIConnections()

    enum Status: Equatable {
        case notInstalled
        case ready
        case connected(String)
    }

    enum TestState: Equatable { case idle, testing, passed(String), failed(String) }

    private(set) var detections: [AIProvider: AIProviderDetection] = [:]
    private(set) var serverModels: [AIProvider: Int] = [:]
    private(set) var checking = false
    var messages: [AIProvider: String] = [:]
    var anyLLM: AnyLLMConfig { didSet { Self.save(anyLLM) } }
    private(set) var anyLLMKeySaved = false
    var anyLLMTest: TestState = .idle
    /// The key being typed; cleared once saved (this toolchain has no SwiftUI `@State` macro).
    var keyDraft = ""
    /// Last auth-status answer per CLI (Sign in / Connect), from a free status check.
    var signedIn: [AIProvider: Bool] = [:]
    /// The row whose install command is shown under it.
    var installShown: AIProvider?
    /// Rows with a primary action in flight.
    var busy: Set<AIProvider> = []
    /// Bumped by every edit, key change and disconnect so an older endpoint test cannot report for the new setup.
    @ObservationIgnored private var anyLLMGeneration = 0
    @ObservationIgnored var signInWatch: [AIProvider: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        anyLLM = UserDefaults.standard.data(forKey: AnyLLMConfig.defaultsKey)
            .flatMap { try? JSONDecoder().decode(AnyLLMConfig.self, from: $0) } ?? AnyLLMConfig()
        anyLLMKeySaved = Keychain.get(AnyLLMConfig.keyAccount) != nil
        detections = AIProviderDetector.detectAll()
    }

    private static func save(_ config: AnyLLMConfig) {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: AnyLLMConfig.defaultsKey) }
    }

    // MARK: Status

    func status(_ provider: AIProvider, services: OnboardingServices) -> Status {
        switch provider {
        case .claudeCode:
            return services.isConnected(.claude) ? .connected("Hooks installed. Approvals reach the notch.") : (installed(provider) ? .ready : .notInstalled)
        case .codex:
            return services.isConnected(.codex) ? .connected("Hooks installed. Approvals reach the notch.") : (installed(provider) ? .ready : .notInstalled)
        case .cursor, .gemini:
            guard let agent = provider.hookAgent else { return .notInstalled }
            if AgentHookInstaller.isInstalled(agent) { return .connected("Hooks installed. Runs show in the notch.") }
            return installed(provider) || AgentHookInstaller.isAvailable(agent) ? .ready : .notInstalled
        case .grok, .chatgpt:
            guard installed(provider) else { return .notInstalled }
            return defaults.bool(forKey: enabledKey(provider)) ? .connected("The app opens with your question.") : .ready
        case .ollama, .lmStudio:
            if let count = serverModels[provider] { return .connected(count == 1 ? "Running, 1 model." : "Running, \(count) models.") }
            return installed(provider) ? .ready : .notInstalled
        case .anyLLM:
            guard anyLLM.isComplete else { return .notInstalled }
            if case .passed(let text) = anyLLMTest { return .connected(text) }
            // A refused or unreachable endpoint is never "saved and connected".
            if case .failed = anyLLMTest { return .ready }
            return defaults.bool(forKey: enabledKey(.anyLLM)) ? .connected("Endpoint saved.") : .ready
        }
    }

    func installed(_ provider: AIProvider) -> Bool { detections[provider]?.isInstalled == true }

    /// What the row says under the name.
    func detail(_ provider: AIProvider, services: OnboardingServices) -> String {
        if let message = messages[provider] { return message }
        if provider.kind == .hooked, installed(provider), signedIn[provider] == false {
            return "Found on this Mac, not signed in. Sign in opens Terminal with its own login."
        }
        switch status(provider, services: services) {
        case .connected(let text): return text
        case .ready:
            switch provider.kind {
            case .hooked: return "Found on this Mac. Connect to follow it from the notch."
            case .app: return "Found on this Mac. Open it to hand questions to it."
            case .localServer: return provider == .ollama ? "Found on this Mac. Start runs Ollama." : "Found on this Mac. Start runs the LM Studio server."
            case .endpoint: return "Test the endpoint to connect it."
            }
        case .notInstalled:
            switch provider.kind {
            case .endpoint: return "Add a base URL and a model below."
            default: return "Not found on this Mac. Install shows the official command."
            }
        }
    }

    // MARK: Actions

    func connect(_ provider: AIProvider, services: OnboardingServices) {
        messages[provider] = nil
        switch provider {
        case .claudeCode: services.connect(.claude); messages[provider] = services.connectMessage
        case .codex: services.connect(.codex); messages[provider] = services.connectMessage
        case .cursor, .gemini:
            guard let agent = provider.hookAgent else { return }
            do { try AgentHookInstaller.install(agent); messages[provider] = "Connected." } catch { messages[provider] = error.localizedDescription }
        case .grok, .chatgpt, .ollama, .lmStudio:
            defaults.set(true, forKey: enabledKey(provider))
            Task { await refresh(only: provider) }
        case .anyLLM:
            defaults.set(true, forKey: enabledKey(.anyLLM))
            Task { await testAnyLLM() }
        }
        services.refresh()
    }

    func disconnect(_ provider: AIProvider, services: OnboardingServices) {
        messages[provider] = nil
        switch provider {
        case .claudeCode: services.permissions.disconnectClaudeCode()
        case .codex, .cursor, .gemini:
            if let agent = provider.hookAgent { try? AgentHookInstaller.uninstall(agent) }
        default:
            defaults.set(false, forKey: enabledKey(provider))
            if provider == .anyLLM { anyLLMGeneration &+= 1; anyLLMTest = .idle }
        }
        serverModels[provider] = nil
        services.refresh()
    }

    func canDisconnect(_ provider: AIProvider) -> Bool { provider != .ollama && provider != .lmStudio }

    /// Detects installed tools and probes the local servers. Only files and loopback ports are
    /// touched, so nothing paid can run.
    func refresh(only provider: AIProvider? = nil) async {
        checking = true
        defer { checking = false }
        detections = AIProviderDetector.detectAll()
        for local in AIProvider.allCases where local.localPort != nil && (provider == nil || provider == local) {
            serverModels[local] = await Self.probe(local)
        }
    }

    private static func probe(_ provider: AIProvider) async -> Int? {
        guard let port = provider.localPort, let path = provider.localProbePath,
              let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let models = json?["models"] as? [Any] { return models.count }
        if let models = json?["data"] as? [Any] { return models.count }
        return 0
    }

    // MARK: Any LLM

    /// Saves a pasted key. An empty value removes the saved key, so callers that submit a draft
    /// (Return in the field) check for empty first. False when the Keychain refused: the caller keeps the draft.
    @discardableResult
    func saveAnyLLMKey(_ key: String) -> Bool {
        anyLLMGeneration &+= 1
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard Keychain.remove(AnyLLMConfig.keyAccount) else {
                anyLLMTest = .failed("Couldn't remove the key. Check Keychain access and try again.")
                return false
            }
            anyLLMKeySaved = false
        } else {
            guard Keychain.set(trimmed, for: AnyLLMConfig.keyAccount) else {
                anyLLMTest = .failed("Couldn't save the key to your Keychain. It is still in the field.")
                return false
            }
            anyLLMKeySaved = true
        }
        anyLLMTest = .idle
        return true
    }

    /// The address or model changed: the earlier test and the "connected" flag no longer apply.
    func endpointEdited() {
        anyLLMGeneration &+= 1
        anyLLMTest = .idle
        messages[.anyLLM] = nil
        defaults.set(false, forKey: enabledKey(.anyLLM))
    }

    /// Lists the endpoint's models. No tokens are spent; a 401 means the address is right and the key is wrong.
    func testAnyLLM() async {
        guard let url = anyLLM.modelsURL else { anyLLMTest = .failed("Add a base URL first."); return }
        if anyLLM.isInsecureRemote { anyLLMTest = .failed("Plain http is only allowed for this Mac. Use https."); return }
        // One test at a time; a second press while one is running changes nothing.
        if case .testing = anyLLMTest { return }
        anyLLMTest = .testing
        let generation = anyLLMGeneration
        var request = URLRequest(url: url, timeoutInterval: 10)
        if let key = Keychain.get(AnyLLMConfig.keyAccount) { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let result: TestState
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200..<300: result = .passed("Connected to \(url.host ?? "the endpoint").")
            case 401, 403: result = .failed("The endpoint refused the key.")
            case 404: result = .passed("Reached \(url.host ?? "the endpoint"). It does not list models.")
            case let code: result = .failed("The endpoint answered \(code).")
            }
        } catch {
            result = .failed("Could not reach \(url.host ?? "the endpoint").")
        }
        // An edit, a key change or a disconnect while the request ran made this answer about another setup.
        guard generation == anyLLMGeneration else { return }
        anyLLMTest = result
        // The flag is set before a test starts (Connect, Test); a failed test takes it back.
        if case .failed = result { defaults.set(false, forKey: enabledKey(.anyLLM)) }
    }

    /// One answer from the endpoint, for routing a question to it.
    func askAnyLLM(_ prompt: String) async -> String? {
        guard let request = anyLLM.request(prompt: prompt, key: Keychain.get(AnyLLMConfig.keyAccount)),
              let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return AnyLLMConfig.answer(from: data)
    }

    // MARK: Flags

    func enabledKey(_ provider: AIProvider) -> String { "ai.enabled.\(provider.rawValue)" }

    /// "Offer for new chats". Claude Code and Codex keep the toggles Settings already had.
    func offers(_ provider: AIProvider) -> Bool {
        switch provider {
        case .claudeCode: SettingsStore.shared.bool("integrations.offerClaude")
        case .codex: SettingsStore.shared.bool("integrations.offerCodex")
        default: defaults.object(forKey: provider.offerKey) as? Bool ?? false
        }
    }

    func setOffers(_ provider: AIProvider, _ on: Bool) {
        switch provider {
        case .claudeCode: SettingsStore.shared.set("integrations.offerClaude", on ? "true" : "false")
        case .codex: SettingsStore.shared.set("integrations.offerCodex", on ? "true" : "false")
        default: defaults.set(on, forKey: provider.offerKey)
        }
    }
}
