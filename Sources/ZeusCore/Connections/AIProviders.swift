import Foundation

/// Every AI Zeus can follow, hand work to, or answer with. Detection only looks for files, so
/// finding one never starts a paid call.
public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case claudeCode, codex, cursor, grok, gemini, chatgpt, ollama, lmStudio, anyLLM

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .grok: "Grok Bot"
        case .gemini: "Gemini"
        case .chatgpt: "ChatGPT"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .anyLLM: "Any LLM"
        }
    }

    public enum Kind: Sendable {
        /// A command line tool whose hooks Zeus can add, so activity and approvals reach the notch.
        case hooked
        /// A desktop app Zeus opens and hands a prompt to.
        case app
        /// A model server on this Mac (nothing leaves it).
        case localServer
        /// Any OpenAI compatible endpoint (base URL, model and key).
        case endpoint
    }

    public var kind: Kind {
        switch self {
        case .claudeCode, .codex, .cursor, .gemini: .hooked
        case .grok, .chatgpt: .app
        case .ollama, .lmStudio: .localServer
        case .anyLLM: .endpoint
        }
    }

    /// Command line tool name, when the provider has one.
    public var binary: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .cursor: "cursor-agent"
        case .gemini: "gemini"
        case .ollama: "ollama"
        case .lmStudio: "lms"
        case .grok, .chatgpt, .anyLLM: nil
        }
    }

    /// Application bundle names looked for in /Applications and ~/Applications.
    public var appNames: [String] {
        switch self {
        case .claudeCode: ["Claude"]
        case .codex: ["Codex"]
        case .cursor: ["Cursor"]
        case .gemini: ["Gemini"]
        case .grok: ["Grok Bot", "Grok"]
        case .chatgpt: ["ChatGPT"]
        case .ollama: ["Ollama"]
        case .lmStudio: ["LM Studio"]
        case .anyLLM: []
        }
    }

    /// The loopback port a local server answers on.
    public var localPort: Int? {
        switch self {
        case .ollama: 11434
        case .lmStudio: 1234
        default: nil
        }
    }

    public var localProbePath: String? {
        switch self {
        case .ollama: "/api/tags"
        case .lmStudio: "/v1/models"
        default: nil
        }
    }

    /// The matching CLI engine of the model router, for providers it can run headless.
    public var routerEngine: RouterEngine? {
        switch self {
        case .claudeCode: .claude
        case .codex: .codex
        case .cursor: .cursorAgent
        case .gemini: .gemini
        case .grok: .grok
        case .ollama: .ollama
        case .chatgpt, .lmStudio, .anyLLM: nil
        }
    }

    /// The hook installer entry, for the tools Zeus can follow live.
    public var hookAgent: AgentHookConfig.Agent? {
        switch self {
        case .codex: .codex
        case .gemini: .gemini
        case .cursor: .cursor
        default: nil
        }
    }

    public var blurb: String {
        switch self {
        case .claudeCode: "Activity and approvals reach the notch."
        case .codex: "Activity and approvals reach the notch."
        case .cursor: "Cursor Agent runs are followed from the notch."
        case .gemini: "Gemini CLI sessions are followed from the notch."
        case .grok: "Open the Grok app. Prompt handoff is not supported."
        case .chatgpt: "Open the ChatGPT app. Prompt handoff is not supported."
        case .ollama: "Models that run on this Mac. Nothing leaves it."
        case .lmStudio: "Models served by LM Studio on this Mac."
        case .anyLLM: "Any OpenAI compatible endpoint, with your own key."
        }
    }

    public var offerKey: String { "ai.offer.\(rawValue)" }

    /// Only these agents have an implemented New chat launch path.
    public var supportsNewChats: Bool {
        switch self {
        case .claudeCode, .codex, .cursor, .gemini: true
        default: false
        }
    }
}

/// What Zeus found for one provider on this Mac.
public struct AIProviderDetection: Equatable, Sendable {
    public var cliPath: String?
    public var appPath: String?
    public var isInstalled: Bool { cliPath != nil || appPath != nil }
    public init(cliPath: String? = nil, appPath: String? = nil) { self.cliPath = cliPath; self.appPath = appPath }
}

public enum AIProviderDetector {
    public static var defaultSearchDirectories: [String] {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local",
                "\(home)/.cursor/bin", "\(home)/.lmstudio/bin", "\(home)/.bun/bin", "\(home)/.npm-global/bin", "/usr/bin"]
    }

    public static var defaultAppDirectories: [String] { ["/Applications", "\(NSHomeDirectory())/Applications"] }

    public static func detect(_ provider: AIProvider, searchDirectories: [String] = defaultSearchDirectories,
                              appDirectories: [String] = defaultAppDirectories,
                              isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> AIProviderDetection {
        var found = AIProviderDetection()
        if let binary = provider.binary {
            found.cliPath = searchDirectories.map { "\($0)/\(binary)" }.first(where: isExecutable)
        }
        found.appPath = appDirectories.flatMap { directory in provider.appNames.map { "\(directory)/\($0).app" } }.first(where: exists)
        return found
    }

    public static func detectAll(searchDirectories: [String] = defaultSearchDirectories,
                                 appDirectories: [String] = defaultAppDirectories,
                                 isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                                 exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [AIProvider: AIProviderDetection] {
        Dictionary(uniqueKeysWithValues: AIProvider.allCases.map {
            ($0, detect($0, searchDirectories: searchDirectories, appDirectories: appDirectories, isExecutable: isExecutable, exists: exists))
        })
    }
}

/// The OpenAI compatible endpoint behind "Any LLM". Base URL and model live in UserDefaults;
/// the key lives in the Keychain item, read once and cached by `KeychainStore`.
public struct AnyLLMConfig: Codable, Equatable, Sendable {
    public static let defaultsKey = "ai.anyllm.config"
    public static let keyAccount = "anyllm-api-key"

    public var baseURL: String
    public var model: String

    public init(baseURL: String = "", model: String = "") { self.baseURL = baseURL; self.model = model }

    /// Invalid credential-bearing URL drafts stay visible for correction but are never written
    /// to preferences. The separate Keychain field is the only supported credential input.
    public var configurationForPreferences: AnyLLMConfig {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URLComponents(string: text), url.user != nil || url.password != nil else { return self }
        return AnyLLMConfig(baseURL: "", model: model)
    }

    /// Where chat requests go: the base URL plus `/chat/completions`, tolerating a trailing
    /// slash or a pasted full path.
    public var chatURL: URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/chat/completions") { text.removeLast("/chat/completions".count) }
        guard let url = URL(string: text + "/chat/completions"), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    public var modelsURL: URL? {
        guard let chat = chatURL else { return nil }
        return chat.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models")
    }

    public var isComplete: Bool { chatURL != nil && !model.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A plain `http` endpoint is only acceptable on this Mac.
    public var isInsecureRemote: Bool {
        guard let url = chatURL, url.scheme == "http" else { return false }
        return !AnyLLMEndpointPolicy.isLoopback(url.host ?? "")
    }

    public func request(prompt: String, key: String?, system: String? = nil) -> URLRequest? {
        guard isComplete, let url = chatURL, AnyLLMEndpointPolicy.permits(url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": prompt])
        let body: [String: Any] = ["model": model.trimmingCharacters(in: .whitespaces), "messages": messages, "stream": false]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The same request with `stream: true`, for a live answer. `keepAlive` is the Ollama hint (`30m`).
    public func streamingRequest(prompt: String, key: String?, system: String? = nil, keepAlive: String? = nil) -> URLRequest? {
        guard isComplete, let url = chatURL, AnyLLMEndpointPolicy.permits(url) else { return nil }
        guard let model = ModelCap.gatedHTTPModel(model.trimmingCharacters(in: .whitespaces)) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let body = OpenAICompat.body(model: model, prompt: prompt, system: system, keepAlive: keepAlive)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The assistant text of a chat completion response.
    public static func answer(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
