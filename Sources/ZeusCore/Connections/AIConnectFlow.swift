import Foundation

// One primary button per AI in Settings › Integrations that does the right next thing:
// Install (show the official command), Sign in (the CLI's own login in Terminal), Connect
// (Zeus's hooks plus a free status check), Open (an app), Start (a local server), Test (an
// endpoint). Pure so every provider's path is tested with fake detection and status runners.
//
// The login and status commands below were checked against each CLI's --help on Tony's Mac
// (claude 2.1.296, codex-cli 0.166.0, gemini 0.64.0, cursor-agent 2026.10.22). None of them
// spends a token: status subcommands read the local login only.

/// What Zeus knows about one provider right now.
public struct AIConnectFacts: Equatable, Sendable {
    public var installed: Bool
    /// nil while unknown (not checked yet, or the CLI has no way to tell).
    public var signedIn: Bool?
    /// Zeus's hooks are in place (hooked CLIs), or the app / endpoint is switched on.
    public var linked: Bool
    /// A local server answers, or an app is running.
    public var running: Bool
    /// Endpoint only: base URL and model filled in.
    public var configured: Bool
    /// Endpoint only: nil until tested.
    public var testPassed: Bool?

    public init(installed: Bool = false, signedIn: Bool? = nil, linked: Bool = false, running: Bool = false,
                configured: Bool = false, testPassed: Bool? = nil) {
        self.installed = installed
        self.signedIn = signedIn
        self.linked = linked
        self.running = running
        self.configured = configured
        self.testPassed = testPassed
    }
}

/// The row's state, and so its one primary button.
public enum AIConnectStep: Equatable, Sendable {
    /// Not on this Mac: show the official install command (never run it) and the docs.
    case install
    /// Installed, not signed in: open Terminal with the CLI's own login.
    case signIn
    /// Signed in (or nothing to sign in to): install hooks / switch it on and check.
    case connect
    /// An app that is installed but not opened through Zeus yet.
    case openApp
    /// A local server that is installed but not answering.
    case startServer
    /// An endpoint without a base URL or model.
    case configure
    /// An endpoint that is filled in but not tested (or failed its test).
    case test
    case connected

    /// The primary button's title.
    public var buttonTitle: String {
        switch self {
        case .install: "Install"
        case .signIn: "Sign in"
        case .connect: "Connect"
        case .openApp: "Open"
        case .startServer: "Start"
        case .configure: "Paste key"
        case .test: "Test"
        case .connected: "Connected"
        }
    }
}

public enum AIConnectFlow {
    public static func step(for provider: AIProvider, facts: AIConnectFacts) -> AIConnectStep {
        switch provider.kind {
        case .hooked:
            guard facts.installed else { return .install }
            if facts.signedIn == false { return .signIn }
            // Hooks in place and not known to be signed out (the free check may still be running).
            return facts.linked ? .connected : .connect
        case .app:
            guard facts.installed else { return .install }
            // Existing behaviour: running, or switched on once, counts as connected.
            return facts.linked || facts.running ? .connected : .openApp
        case .localServer:
            if facts.running { return .connected }
            return facts.installed ? .startServer : .install
        case .endpoint:
            guard facts.configured else { return .configure }
            return facts.testPassed == true ? .connected : .test
        }
    }

    // MARK: Install

    /// The official install command, shown with a Copy button. Zeus never runs it.
    public static func installCommand(_ provider: AIProvider) -> String? {
        switch provider {
        case .claudeCode: "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex: "npm install -g @openai/codex"
        case .gemini: "npm install -g @google/gemini-cli"
        case .cursor: "curl https://cursor.com/install -fsS | bash"
        case .ollama: "brew install ollama"
        case .lmStudio, .chatgpt, .grok, .anyLLM: nil
        }
    }

    /// Where the official install and sign-in instructions live.
    public static func docsURL(_ provider: AIProvider) -> URL? {
        let text: String = switch provider {
        case .claudeCode: "https://docs.claude.com/en/docs/claude-code/setup"
        case .codex: "https://github.com/openai/codex#quickstart"
        case .gemini: "https://github.com/google-gemini/gemini-cli#-installation"
        case .cursor: "https://cursor.com/docs/cli/installation"
        case .ollama: "https://ollama.com/download"
        case .lmStudio: "https://lmstudio.ai/download"
        case .chatgpt: "https://openai.com/chatgpt/desktop/"
        case .grok: "https://grok.com/download"
        case .anyLLM: "https://platform.openai.com/docs/api-reference/chat"
        }
        return URL(string: text)
    }

    // MARK: Sign in

    /// The CLI's own login, run in Terminal for Tony to finish. Gemini has no login subcommand:
    /// its first interactive run asks how to sign in.
    public static func loginArguments(_ provider: AIProvider) -> [String]? {
        switch provider {
        case .claudeCode: ["auth", "login"]
        case .codex: ["login"]
        case .cursor: ["login"]
        case .gemini: []
        default: nil
        }
    }

    /// One line shown in Terminal above the login.
    public static func loginHint(_ provider: AIProvider) -> String {
        switch provider {
        case .gemini: "Choose \"Sign in with Google\" when Gemini asks, finish in the browser, then type /quit."
        default: "Finish signing in in the browser that opens, then come back to Zeus and click Connect."
        }
    }

    /// The `.command` script Terminal runs for Sign in. Paths are single-quoted for the shell.
    public static func signInScript(_ provider: AIProvider, executable: String) -> String? {
        guard let arguments = loginArguments(provider) else { return nil }
        let command = ([executable] + arguments).map(shellQuote).joined(separator: " ")
        return """
        #!/bin/zsh -l
        clear
        echo \(shellQuote("Zeus: signing in to \(provider.title)."))
        echo \(shellQuote(loginHint(provider)))
        echo
        \(command)
        echo
        echo \(shellQuote("You can close this window and click Connect in Zeus."))

        """
    }

    public static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Status (no paid call)

    /// The CLI's own auth-status subcommand. nil: the CLI has none (Gemini), so its files are read.
    public static func statusArguments(_ provider: AIProvider) -> [String]? {
        switch provider {
        case .claudeCode: ["auth", "status", "--json"]
        case .codex: ["login", "status"]
        case .cursor: ["status", "--format", "json"]
        default: nil
        }
    }

    /// Reads a status command's result. nil when it can't tell (an older CLI without the
    /// subcommand, or output it doesn't recognise), which leaves the Connect button available.
    public static func signedIn(_ provider: AIProvider, exitCode: Int32, output: String) -> Bool? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if let json = jsonObject(in: text) {
            switch provider {
            case .claudeCode: if let value = json["loggedIn"] as? Bool { return value }
            case .cursor: if let value = json["isAuthenticated"] as? Bool { return value }
            default: break
            }
        }
        if lowered.contains("not logged in") || lowered.contains("not authenticated") || lowered.contains("logged out")
            || lowered.contains("not signed in") {
            return false
        }
        if exitCode == 0, lowered.contains("logged in") || lowered.contains("authenticated") || lowered.contains("signed in") {
            return true
        }
        if lowered.contains("unknown command") || lowered.contains("unrecognized") || lowered.contains("unexpected argument") {
            return nil
        }
        return exitCode == 0 ? nil : false
    }

    /// Gemini CLI keeps its Google login in ~/.gemini/oauth_creds.json, or uses a key from the
    /// environment, or Vertex / Cloud Shell credentials named in settings.json.
    public static func geminiSignedIn(oauthCredentialsExist: Bool, settings: Data?, environment: [String: String]) -> Bool {
        if oauthCredentialsExist { return true }
        for key in ["GEMINI_API_KEY", "GOOGLE_API_KEY"] where environment[key]?.isEmpty == false { return true }
        if environment["GOOGLE_GENAI_USE_VERTEXAI"]?.lowercased() == "true" { return true }
        guard let settings, let json = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] else { return false }
        let selected = ((json["security"] as? [String: Any])?["auth"] as? [String: Any])?["selectedType"] as? String
            ?? json["selectedAuthType"] as? String
        return ["vertex-ai", "cloud-shell", "compute-default-credentials"].contains(selected ?? "")
    }

    // MARK: Local servers

    /// How Start launches a local server: an app to open, else the CLI with these arguments.
    public static func startCommand(_ provider: AIProvider, appInstalled: Bool) -> (app: String?, arguments: [String])? {
        switch provider {
        case .ollama: appInstalled ? ("Ollama", []) : (nil, ["serve"])
        case .lmStudio: appInstalled ? ("LM Studio", []) : (nil, ["server", "start"])
        default: nil
        }
    }

    // MARK: Endpoint test

    /// The endpoint test lists models and spends nothing; a model larger than Haiku / mini size
    /// is refused before any request, the same rule ModelCap applies to every CLI launch.
    public static func endpointModelProblem(_ model: String) -> String? {
        let name = model.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "Add a model name first." }
        guard ModelCap.isAllowed(name) else { return "\(name) is larger than Zeus uses. Pick a Haiku or mini size model." }
        return nil
    }

    public static func hookConnectionMessage(_ provider: AIProvider, signedIn: Bool?) -> String {
        switch signedIn {
        case true: "Hooks installed. \(provider.title) is signed in."
        case false: "Hooks installed, but \(provider.title) isn't signed in. Click Sign in."
        case nil: "Hooks installed. Sign-in status could not be verified; check the provider's app or CLI."
        }
    }

    /// One-click presets for the endpoint card. The model is a small one; Tony can change it.
    public static let endpointPresets: [AIEndpointPreset] = [
        AIEndpointPreset(title: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-5-mini"),
    ]

    static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// A one-click fill for the Any LLM card.
public struct AIEndpointPreset: Equatable, Identifiable, Sendable {
    public let title: String
    public let baseURL: String
    public let model: String
    public var id: String { title }
}
