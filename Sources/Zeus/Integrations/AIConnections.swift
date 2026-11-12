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

    typealias TestState = AnyLLMEndpointValidation.State

    private(set) var detections: [AIProvider: AIProviderDetection] = [:]
    /// False until the first background look at this Mac finishes: rows say "Checking" instead of "not found".
    private(set) var detected = false
    /// Hook files and config folders, read off the main thread by `detect()`. `status` runs in view
    /// bodies, so it never touches the disk.
    private(set) var hookInstalled: [AgentHookConfig.Agent: Bool] = [:]
    private(set) var hookAvailable: [AgentHookConfig.Agent: Bool] = [:]
    private(set) var serverModels: [AIProvider: Int] = [:]
    private(set) var checking = false
    /// Counts overlapping refreshes, so one finishing cannot clear `checking` while another still probes.
    @ObservationIgnored private var refreshes = OverlapCounter()
    /// Background looks at the hook files. Connect and Disconnect invalidate it, so a look that started before the
    /// click cannot put the old "not connected" back; the newest look wins over an older one.
    @ObservationIgnored private var hookReads = LatestRun()
    var messages: [AIProvider: String] = [:]
    var anyLLM: AnyLLMConfig {
        didSet {
            Self.save(anyLLM)
            if oldValue != anyLLM { endpointEdited() }
        }
    }
    private(set) var anyLLMKeySaved = false
    private var endpointValidation = AnyLLMEndpointValidation()
    var anyLLMTest: TestState { endpointValidation.state }
    /// The key being typed; cleared once saved (this toolchain has no SwiftUI `@State` macro).
    var keyDraft = ""
    /// Last auth-status answer per CLI (Sign in / Connect), from a free status check.
    var signedIn: [AIProvider: Bool] = [:]
    /// The row whose install command is shown under it.
    var installShown: AIProvider?
    /// Rows with a primary action in flight.
    var busy: Set<AIProvider> = []
    private var offerRevision = 0
    @ObservationIgnored var signInWatch: [AIProvider: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        anyLLM = UserDefaults.standard.data(forKey: AnyLLMConfig.defaultsKey)
            .flatMap { try? JSONDecoder().decode(AnyLLMConfig.self, from: $0) } ?? AnyLLMConfig()
        anyLLMKeySaved = Keychain.get(AnyLLMConfig.keyAccount) != nil
        // Remove credential-bearing URL values saved by earlier builds without using them.
        Self.save(anyLLM)
    }

    private static func save(_ config: AnyLLMConfig) {
        if let data = try? JSONEncoder().encode(config.configurationForPreferences) { UserDefaults.standard.set(data, forKey: AnyLLMConfig.defaultsKey) }
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
            if hookInstalled[agent] == true { return .connected("Hooks installed. Runs show in the notch.") }
            return installed(provider) || hookAvailable[agent] == true ? .ready : .notInstalled
        case .grok, .chatgpt:
            guard installed(provider) else { return .notInstalled }
            return defaults.bool(forKey: enabledKey(provider)) ? .connected("Opens the app. Prompt handoff is not supported.") : .ready
        case .ollama, .lmStudio:
            if let count = serverModels[provider] { return .connected(count == 1 ? "Running, 1 model." : "Running, \(count) models.") }
            return installed(provider) ? .ready : .notInstalled
        case .anyLLM:
            guard anyLLM.isComplete else { return .notInstalled }
            if case .passed(let text) = anyLLMTest { return .connected(text) }
            // A refused or unreachable endpoint is never "saved and connected".
            if case .failed = anyLLMTest { return .ready }
            return .ready
        }
    }

    func installed(_ provider: AIProvider) -> Bool { detections[provider]?.isInstalled == true }

    /// What the row says under the name.
    func detail(_ provider: AIProvider, services: OnboardingServices) -> String {
        if let message = messages[provider] { return message }
        if !detected, provider.kind != .endpoint { return "Checking this Mac\u{2026}" }
        if provider.kind == .hooked, installed(provider), signedIn[provider] == false {
            return "Found on this Mac, not signed in. Sign in opens Terminal with its own login."
        }
        switch status(provider, services: services) {
        case .connected(let text): return text
        case .ready:
            switch provider.kind {
            case .hooked: return "Found on this Mac. Connect to follow it from the notch."
            case .app: return "Found on this Mac. Open the app here; prompt handoff is not supported."
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
        case .codex:
            services.connect(.codex)
            messages[provider] = services.connectMessage
            // The row reads `hookInstalled`; without this it said "Ready" until the next background look.
            if services.codexConnected, let agent = provider.hookAgent {
                hookReads.invalidate()
                hookInstalled[agent] = true
            }
        case .cursor, .gemini:
            guard let agent = provider.hookAgent else { return }
            do {
                try AgentHookInstaller.install(agent)
                hookReads.invalidate()
                hookInstalled[agent] = true
                messages[provider] = "Connected."
            } catch { messages[provider] = error.localizedDescription }
        case .grok, .chatgpt, .ollama, .lmStudio:
            defaults.set(true, forKey: enabledKey(provider))
            Task { await refresh(only: provider) }
        case .anyLLM:
            Task { await testAnyLLM() }
        }
        services.refresh()
    }

    func disconnect(_ provider: AIProvider, services: OnboardingServices) {
        messages[provider] = nil
        switch provider {
        case .claudeCode: services.permissions.disconnectClaudeCode()
        case .codex, .cursor, .gemini:
            if let agent = provider.hookAgent {
                try? AgentHookInstaller.uninstall(agent)
                hookReads.invalidate()
                hookInstalled[agent] = AgentHookInstaller.isInstalled(agent)
            }
        default:
            defaults.set(false, forKey: enabledKey(provider))
            if provider == .anyLLM { endpointEdited() }
        }
        serverModels[provider] = nil
        services.refresh()
    }

    func canDisconnect(_ provider: AIProvider) -> Bool { provider != .ollama && provider != .lmStudio }

    /// Detects installed tools and probes the local servers. Only files and loopback ports are
    /// touched, so nothing paid can run.
    func refresh(only provider: AIProvider? = nil) async {
        refreshes.begin()
        checking = true
        defer { refreshes.end(); checking = refreshes.isActive }
        await detect()
        for local in AIProvider.allCases where local.localPort != nil && (provider == nil || provider == local) {
            serverModels[local] = await Self.probe(local)
        }
    }

    /// Looks for the CLIs, apps and hook files on a background thread, then publishes the answer once.
    func detect() async {
        let read = hookReads.begin()
        let snapshot = await Task.detached(priority: .userInitiated) { () -> ([AIProvider: AIProviderDetection], [AgentHookConfig.Agent: Bool], [AgentHookConfig.Agent: Bool]) in
            var installed: [AgentHookConfig.Agent: Bool] = [:], available: [AgentHookConfig.Agent: Bool] = [:]
            for agent in AgentHookConfig.Agent.allCases {
                installed[agent] = AgentHookInstaller.isInstalled(agent)
                available[agent] = AgentHookInstaller.isAvailable(agent)
            }
            return (AIProviderDetector.detectAll(), installed, available)
        }.value
        detections = snapshot.0
        hookAvailable = snapshot.2
        if hookReads.isCurrent(read) {
            hookInstalled = snapshot.1
        } else {
            // A click changed one agent while this look ran: keep what the click set, fill in the rest.
            for (agent, value) in snapshot.1 where hookInstalled[agent] == nil { hookInstalled[agent] = value }
        }
        detected = true
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
        endpointEdited()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard Keychain.remove(AnyLLMConfig.keyAccount) else {
                endpointRejected("Couldn't remove the key. Check Keychain access and try again.")
                return false
            }
            anyLLMKeySaved = false
        } else {
            guard Keychain.set(trimmed, for: AnyLLMConfig.keyAccount) else {
                endpointRejected("Couldn't save the key to your Keychain. It is still in the field.")
                return false
            }
            anyLLMKeySaved = true
        }
        return true
    }

    /// The address or model changed: the earlier test and the "connected" flag no longer apply.
    func endpointEdited() {
        endpointValidation.invalidate()
        messages[.anyLLM] = nil
        defaults.set(false, forKey: enabledKey(.anyLLM))
    }

    func endpointRejected(_ reason: String) {
        endpointValidation.invalidate(reason: reason)
        defaults.set(false, forKey: enabledKey(.anyLLM))
    }

    /// Lists the endpoint's models. No tokens are spent; a 401 means the address is right and the key is wrong.
    func testAnyLLM() async {
        guard let url = anyLLM.modelsURL else { endpointRejected("Add a base URL first."); return }
        guard AnyLLMEndpointPolicy.permits(url) else {
            endpointRejected("Use https for remote servers and keep credentials in the API key field.")
            return
        }
        // One test at a time; a second press while one is running changes nothing.
        guard let generation = endpointValidation.begin() else { return }
        defaults.set(false, forKey: enabledKey(.anyLLM))
        var request = URLRequest(url: url, timeoutInterval: 10)
        if let key = Keychain.get(AnyLLMConfig.keyAccount) { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let result: TestState
        do {
            let (_, response) = try await AnyLLMHTTPTransport.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200..<300: result = .passed("Connected to \(url.host ?? "the endpoint").")
            case 401, 403: result = .failed("The endpoint refused the key.")
            case 300..<400: result = .failed("The endpoint redirected. Save its final address, then test again.")
            case 404: result = .failed("The endpoint did not expose a models list. Check its API base URL.")
            case let code: result = .failed("The endpoint answered \(code).")
            }
        } catch {
            result = .failed("Could not reach \(url.host ?? "the endpoint").")
        }
        // An edit, a key change or a disconnect while the request ran made this answer about another setup.
        guard endpointValidation.complete(result, generation: generation) else { return }
        defaults.set(endpointValidation.isApproved, forKey: enabledKey(.anyLLM))
    }

    /// One answer from the endpoint, for routing a question to it.
    func askAnyLLM(_ prompt: String) async -> String? {
        guard let request = anyLLM.request(prompt: prompt, key: Keychain.get(AnyLLMConfig.keyAccount)),
              let (data, response) = try? await AnyLLMHTTPTransport.data(for: request),
              let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
        return AnyLLMConfig.answer(from: data)
    }

    // MARK: Flags

    func enabledKey(_ provider: AIProvider) -> String { "ai.enabled.\(provider.rawValue)" }

    /// "Offer for new chats". Claude Code and Codex keep the toggles Settings already had.
    func offers(_ provider: AIProvider) -> Bool {
        _ = offerRevision
        return switch provider {
        case .claudeCode: SettingsStore.shared.bool("integrations.offerClaude")
        case .codex: SettingsStore.shared.bool("integrations.offerCodex")
        case .cursor, .gemini: defaults.object(forKey: provider.offerKey) as? Bool ?? true
        default: false
        }
    }

    func setOffers(_ provider: AIProvider, _ on: Bool) {
        guard provider.supportsNewChats else { return }
        switch provider {
        case .claudeCode: SettingsStore.shared.set("integrations.offerClaude", on ? "true" : "false")
        case .codex: SettingsStore.shared.set("integrations.offerCodex", on ? "true" : "false")
        default: defaults.set(on, forKey: provider.offerKey)
        }
        offerRevision &+= 1
    }
}
