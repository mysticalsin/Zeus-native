import Foundation
import Observation
import SwiftUI
import ZeusCore

/// One-shot answers from Codex, Gemini, Cursor Agent, Grok or Ollama: the CLI runs headless,
/// its stdout streams into the answer. Claude keeps its own richer provider.
final class CLIEngineProvider: BrainProvider, @unchecked Sendable {
    let engine: RouterEngine
    let path: String
    let id: ProviderID
    let capabilities: ProviderCapabilities = [.streaming]
    private let lock = NSLock()
    private var running: [UUID: Process] = [:]

    init(engine: RouterEngine, path: String) {
        self.engine = engine
        self.path = path
        id = switch engine {
        case .codex: .codexCLI
        case .gemini: .geminiCLI
        case .cursorAgent: .cursorAgent
        case .ollama: .ollama
        default: .claudeCLI
        }
    }

    func healthCheck() async -> ProviderHealth {
        FileManager.default.isExecutableFile(atPath: path) ? .ready(version: nil) : .notInstalled
    }

    func cancel(turn: UUID) async {
        let process = lock.withLock { running.removeValue(forKey: turn) }
        if let process, process.isRunning { process.interrupt() }
    }

    /// The system prompt and recent turns folded into one prompt, since these CLIs take a
    /// single message in headless mode.
    ///
    /// QA7 round 11 caught these headless, one-shot CLIs (the fallback chain used when Claude is
    /// parked and Gemini is signed out: Codex, Gemini, Grok, Ollama, Cursor Agent) answering a new
    /// question with a repeat of the *previous* answer, a leaked "User"/"Assistant" role word, or
    /// both. The old prompt ended in a literal "User: <question>\nAssistant:" -- a textbook
    /// completion cue that invites a weaker, non-chat-tuned model to keep *completing the
    /// transcript* (writing the next "User:" turn itself, or finishing the pattern with whatever
    /// text statistically follows, which after a short reply is often the same answer again)
    /// rather than treating the last line as an instruction to obey. Framing history as a labelled
    /// past record and the real ask as an instruction in its own paragraph, with an explicit "do
    /// not" list, removes that cue; `ResponseSanitizer` stays as the floor underneath this, for
    /// whatever still slips through.
    static func prompt(for request: BrainRequest) -> String {
        var parts = [request.systemPrompt]
        let history = request.history.suffix(6)
        if !history.isEmpty {
            var lines = ["Earlier in this same conversation, for context only -- do not repeat or continue any of it:"]
            for exchange in history {
                lines.append("- Tony asked: \(exchange.user)")
                lines.append("  You answered: \(exchange.assistant)")
            }
            parts.append(lines.joined(separator: "\n"))
        }
        parts.append("""
        Tony is asking a brand new question now. Answer only this one, from scratch, in your own \
        words. Never repeat an earlier answer verbatim, never continue the conversation yourself, \
        and never write the words "User", "Tony", "Assistant" or "ZEUS" anywhere in your reply -- \
        write nothing but the answer itself, with no labels or prefixes.

        Tony's new question: \(request.transcript)
        """)
        return parts.joined(separator: "\n\n")
    }

    /// The real failure in a CLI's stderr: CLIs print a banner (version, workdir, model, the
    /// prompt) before the error, so take the last "ERROR:"/"Error:" line, else the last line.
    static let silentLimit: TimeInterval = 30
    /// Once a CLI has started answering, this much silence means it stalled mid-stream.
    static let idleLimit: TimeInterval = 120

    /// Stops a CLI that is silent past `firstByte` seconds before its first output, or past
    /// `idleLimit` after it. Checked every 5 s; ends on its own once the process exits.
    static func watch(_ process: Process, state: CLIRunState, firstByte: TimeInterval, onTimeout: @escaping @Sendable () -> Void = {}) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            guard process.isRunning else { return }
            if state.quietFor > (state.hadOutput ? idleLimit : firstByte) {
                state.mark(timedOut: true)
                process.terminate()
                // A CLI that ignores SIGTERM is killed after a grace period.
                DispatchQueue.global().asyncAfter(deadline: .now() + killGrace) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                // The stream ends now, whether or not the process ever cooperates.
                onTimeout()
                return
            }
            watch(process, state: state, firstByte: firstByte, onTimeout: onTimeout)
        }
    }

    /// Seconds a timed-out CLI gets to exit on SIGTERM before SIGKILL.
    static let killGrace: TimeInterval = 3

    /// Whether a CLI exit is abnormal: killed by a signal or a nonzero status.
    nonisolated static func isAbnormalExit(status: Int32, reason: Process.TerminationReason) -> Bool {
        reason == .uncaughtSignal || status != 0
    }

    nonisolated static func errorLine(_ stderr: String) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let error = lines.last { $0.lowercased().hasPrefix("error") } ?? lines.last ?? ""
        let stripped = error.replacingOccurrences(of: #"^(?i)error:?\s*"#, with: "", options: .regularExpression)
        return String(stripped.prefix(200))
    }

    func send(_ request: BrainRequest) -> AsyncThrowingStream<BrainEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            // The prompt (memory, history, question) goes in on stdin, never argv.
            process.arguments = Self.stdinArguments(engine: engine,
                                                    localModel: UserDefaults.standard.string(forKey: "router.ollamaModel") ?? "llama3.2",
                                                    tier: request.deep ? .deep : .fast)
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = CLILocator.searchDirectories.joined(separator: ":")
            environment["ZEUS_INTERNAL"] = "1"
            environment["NO_COLOR"] = "1"
            process.environment = environment
            let directory = ZeusPaths.runDirectory(turn: request.turn)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            process.currentDirectoryURL = directory
            let stdout = Pipe(), stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let stdin = Pipe()
            process.standardInput = stdin
            // A CLI that says nothing for 30 s is stuck (or waiting on a login): stop it so the
            // turn can move on to the next engine instead of hanging the answer.
            let state = CLIRunState()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                state.mark(output: true)
                continuation.yield(.textDelta(String(decoding: data, as: UTF8.self)))
            }
            // stderr is drained as it arrives (only a bounded tail is kept), so a chatty CLI never
            // blocks on a full pipe mid-answer.
            let errorTail = BoundedTail()
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                errorTail.append(data)
            }
            let limit = engine == .cursorAgent ? 20 : Self.silentLimit // Cursor prints only at the end
            let engineTitle = engine.title
            Self.watch(process, state: state, firstByte: limit) {
                stdout.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed("\(engineTitle) gave no answer in time"))
            }
            process.terminationHandler = { [weak self] finished in
                // The per-turn scratch folder is not reused: remove it however the run ended.
                defer { try? FileManager.default.removeItem(at: directory) }
                stderr.fileHandleForReading.readabilityHandler = nil
                if state.timedOut {
                    _ = self?.lock.withLock { self?.running.removeValue(forKey: request.turn) }
                    stdout.fileHandleForReading.readabilityHandler = nil
                    continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed(
                        "\(self?.engine.title ?? "The engine") gave no answer in time"))
                    return
                }
                stdout.fileHandleForReading.readabilityHandler = nil
                let rest = stdout.fileHandleForReading.readDataToEndOfFile()
                if !rest.isEmpty { continuation.yield(.textDelta(String(decoding: rest, as: UTF8.self))) }
                _ = self?.lock.withLock { self?.running.removeValue(forKey: request.turn) }
                if !Self.isAbnormalExit(status: finished.terminationStatus, reason: finished.terminationReason) {
                    continuation.yield(.done(nil))
                    continuation.finish()
                } else {
                    // Any text that already streamed stays on screen; the error marks it incomplete.
                    errorTail.append(stderr.fileHandleForReading.readDataToEndOfFile())
                    let message = Self.errorLine(errorTail.text)
                    let title = self?.engine.title ?? "The engine"
                    let signalled = finished.terminationReason == .uncaughtSignal
                    continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed(
                        message.isEmpty ? (signalled ? "\(title) was stopped before it finished, so the answer is incomplete." : "\(title) stopped with an error.")
                                        : "\(title): \(message)"))
                }
            }
            do {
                try process.run()
                lock.withLock { running[request.turn] = process }
                StdinFeeder.feed(Data(Self.prompt(for: request).utf8), to: stdin.fileHandleForWriting)
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Headless arguments that read the prompt from stdin. Engines that need a `-p` value get a
    /// fixed stub; the stub is appended to (or replaced by) what arrives on stdin.
    static func stdinArguments(engine: RouterEngine, localModel: String, tier: ModelTier) -> [String] {
        let cap = ModelCap.arguments(for: engine, tier: tier)
        let stub = "Answer the message provided on standard input."
        return switch engine {
        case .claude: cap + ["-p"]
        case .codex: ["exec", "--skip-git-repo-check"] + cap + ["-"]
        case .gemini: cap + ["-p", stub]
        case .cursorAgent: cap + ["--trust", "-p", stub, "--output-format", "text"]
        case .grok: ["-p", stub]
        case .ollama: ["run", localModel]
        }
    }
}

/// Which engine answers what: installed CLIs, per-task choices, and the live decision.
@MainActor
@Observable
final class RouterSettings {
    static let shared = RouterSettings()
    private(set) var installed: [RouterEngine: String] = [:]
    private(set) var choices: [RouterTask: RouterChoice] = [:]
    /// Last `/api/tags` probe; stale true until the first voice turn probes (R24 speed).
    private(set) var ollamaHTTPReachable = true
    private let defaults = UserDefaults.standard

    private init() {
        for task in RouterTask.allCases {
            choices[task] = RouterChoice(storageValue: defaults.string(forKey: "router.\(task.rawValue)"))
        }
        refresh()
    }

    /// Looks for the executables only; nothing is launched.
    func refresh() {
        let extras: [RouterEngine: [String]] = [
            .codex: CLILocator.tools.first { $0.name == "codex" }?.extraPaths ?? [],
        ]
        installed = RouterEngine.installed(searchDirectories: CLILocator.searchDirectories, extraPaths: extras)
    }

    func noteOllamaHTTPReachable(_ reachable: Bool) { ollamaHTTPReachable = reachable }

    func set(_ choice: RouterChoice, for task: RouterTask) {
        choices[task] = choice
        defaults.set(choice.storageValue, forKey: "router.\(task.rawValue)")
    }

    func decide(_ task: RouterTask) -> RouterDecision {
        var usage = ModelRouter.usage(from: UsageModel.shared.providers)
        for engine in exhaustedEngines() { usage[engine] = 1 } // out of quota: route around it
        return ModelRouter.route(task: task, installed: Set(installed.keys), usage: usage, choice: choices[task] ?? .auto)
    }

    // MARK: Out-of-quota engines

    /// Engines that answered "you've hit your limit", and until when Zeus routes around them.
    private var exhausted: [RouterEngine: Date] = RouterSettings.loadExhausted() {
        didSet { UserDefaults.standard.set(exhausted.reduce(into: [String: Date]()) { $0[$1.key.rawValue] = $1.value }, forKey: "router.exhausted") }
    }

    private static func loadExhausted() -> [RouterEngine: Date] {
        let saved = UserDefaults.standard.dictionary(forKey: "router.exhausted") as? [String: Date] ?? [:]
        return saved.reduce(into: [:]) { result, item in
            if let engine = RouterEngine(rawValue: item.key), item.value > Date() { result[engine] = item.value }
        }
    }

    /// Whether a brain error is a usage/quota limit (as opposed to a real failure).
    nonisolated static func isQuotaError(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["usage limit", "weekly limit", "hit your limit", "hit your weekly", "rate limit", "quota",
                "spend limit", "session limit", "limit reached", "429"].contains { lowered.contains($0) }
    }

    /// Whether a brain error means the CLI isn't signed in.
    nonisolated static func isSignInError(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["not logged in", "not signed in", "please log in", "please run", "login required", "unauthorized",
                "authentication", "no auth", "oauth", "api key", "401"].contains { lowered.contains($0) }
    }

    /// Whether a brain error is `CLIEngineProvider`'s own silent-for-30s timeout (`"<engine>
    /// gave no answer in time"`) rather than a real failure the CLI itself reported.
    nonisolated static func isTimeoutError(_ text: String) -> Bool {
        text.lowercased().contains("gave no answer in time")
    }

    /// Marks `engine` out of quota for six hours (CLIs reset on their own schedule; six hours keeps
    /// Zeus off it without forgetting it for days).
    func markExhausted(_ engine: RouterEngine, for interval: TimeInterval = 6 * 3600) {
        let now = Date()
        var next = exhausted.filter { $0.value > now } // prune here, never on a read
        next[engine] = now.addingTimeInterval(interval)
        exhausted = next
    }

    /// A pure read: Settings › Intelligence calls this from its view body, so it must not write
    /// observable state (expired entries are skipped here and dropped on the next `markExhausted`).
    func exhaustedEngines(now: Date = Date()) -> [RouterEngine] {
        exhausted.filter { $0.value > now }.map(\.key)
    }

    /// The next installed CLI to try after `failed` ones, skipping out-of-quota engines.
    func fallbackProvider(after failed: Set<RouterEngine>, task: RouterTask? = nil) -> (BrainProvider, RouterEngine)? {
        let out = Set(exhaustedEngines()).union(failed)
        // Codex, Gemini, Claude, Ollama, Grok, Cursor last. HTTP brains are chosen before this chain.
        // A private task only ever falls back to a local engine.
        for engine in ModelRouter.voiceOrder where !out.contains(engine) && (task != .privateLocal || engine.isLocal) {
            if let path = installed[engine] { return (CLIEngineProvider(engine: engine, path: path), engine) }
        }
        return nil
    }

    /// The provider for a prompt, with the decision (for the answer's badge).
    func provider(for prompt: String, claude: BrainProvider?) -> (BrainProvider?, RouterDecision) {
        let decision = decide(RouterTask.classify(prompt))
        guard let engine = decision.engine else { return (nil, decision) }
        if engine == .claude { return (claude, decision) }
        guard let path = installed[engine] else { return (claude, decision) }
        return (CLIEngineProvider(engine: engine, path: path), decision)
    }

    /// Engines that run on this Mac; nothing leaves it.
    nonisolated static func isLocalEngine(_ id: BrainEngineID) -> Bool { id == .ollamaHTTP || id == .ollama }

    /// The healthy engines a task may use, after its privacy rule and the person's explicit
    /// choice. Private tasks keep only local engines. A chosen engine that isn't available
    /// falls back to the rest (still privacy-filtered), as `ModelRouter.route` does.
    nonisolated static func allowedEngines(_ ids: [BrainEngineID], task: RouterTask, choice: RouterChoice) -> [BrainEngineID] {
        if task == .privateLocal { return ids.filter(isLocalEngine) }
        guard case .engine(let chosen) = choice else { return ids }
        let wanted: Set<BrainEngineID> = chosen == .ollama
            ? [.ollamaHTTP, .ollama]
            : Set(BrainEngineID(rawValue: chosen.rawValue).map { [$0] } ?? [])
        let picked = ids.filter { wanted.contains($0) }
        return picked.isEmpty ? ids : picked
    }

    /// Fastest healthy brains for one voice turn, restricted by the task's privacy and provider
    /// choice before any provider (and so any request) exists. The first two are raced.
    /// `claude` is the app's own Claude provider, offered when the `claude` CLI isn't otherwise listed.
    func brainCandidates(task: RouterTask, hasAnthropicKey: Bool, claude: BrainProvider? = nil) -> [(id: String, provider: BrainProvider)] {
        let openAI = Keychain.get("assistant.key.openai").map { !$0.isEmpty } ?? false
        var ordered = BrainRoute.order(hasAnthropicKey: hasAnthropicKey, hasOpenAIKey: openAI,
                                       installed: Set(installed.keys), exhausted: Set(exhaustedEngines()))
        if claude != nil, !exhaustedEngines().contains(.claude), !ordered.contains(.claude) { ordered.append(.claude) }
        let ids = Self.allowedEngines(ordered, task: task, choice: choices[task] ?? .auto)
        return ids.compactMap { id -> (id: String, provider: BrainProvider)? in
            if id == .claude, installed[.claude] == nil, let claude { return ("claude", claude) }
            return candidate(for: id)
        }
    }

    /// Auto routing for callers with no prompt yet (nothing is sent). Prefer the task-aware form.
    func brainCandidates(hasAnthropicKey: Bool) -> [(id: String, provider: BrainProvider)] {
        brainCandidates(task: .quickAnswer, hasAnthropicKey: hasAnthropicKey)
    }

    private func candidate(for id: BrainEngineID) -> (id: String, provider: BrainProvider)? {
        switch id {
        case .ollamaHTTP:
            guard ollamaHTTPReachable else { return nil }
            return ("ollama", OpenAICompatProvider.ollama())
        case .anthropicAPI:
            return ("anthropic-api", AnthropicAPIProvider())
        case .openAIAPI:
            guard let key = Keychain.get("assistant.key.openai"), !key.isEmpty,
                  let model = ModelCap.httpModel(.openAI, tier: .fast) else { return nil }
            return ("openai", OpenAICompatProvider.openAI(model: model, key: key))
        case .codex, .gemini, .claude, .ollama, .grok, .cursorAgent:
            guard let engine = RouterEngine(rawValue: id.rawValue), let path = installed[engine] else { return nil }
            return (engine.rawValue, CLIEngineProvider(engine: engine, path: path))
        }
    }
}

/// The engine's name under a reply; the tooltip says why the router chose it.
struct RouterEngineBadge: View {
    let engine: RouterEngine
    let reason: String?

    var body: some View {
        Text(engine.title)
            .font(TopBarStyle.label(9.5, .semibold))
            .foregroundStyle(engine.isLocal ? Theme.leaf : Theme.cloudSecondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.storm, in: Capsule())
            .overlay(Capsule().strokeBorder(TopBarStyle.tileStroke))
            .help(reason ?? engine.title)
            .accessibilityLabel("Answered by \(engine.title)")
            .accessibilityHint(reason ?? "")
    }
}

/// Settings › Intelligence.
struct RouterSettingsView: View {
    let settings = RouterSettings.shared
    @AppStorage(CodingTool.preferenceKey) private var codingTool = CodingTool.claude.rawValue
    @AppStorage(TerminalApp.preferenceKey) private var terminalApp = "auto"

    var body: some View {
        Form {
            Section {
                ForEach(RouterTask.allCases) { task in
                    VStack(alignment: .leading, spacing: 3) {
                        Picker(task.title, selection: Binding(get: { settings.choices[task] ?? .auto }, set: { settings.set($0, for: task) })) {
                            Text("Auto").tag(RouterChoice.auto)
                            ForEach(task.ranking) { engine in
                                Text(settings.installed[engine] == nil ? "\(engine.title) (not installed)" : engine.title)
                                    .tag(RouterChoice.engine(engine))
                            }
                        }
                        Text(settings.decide(task).reason).font(.callout).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Which AI answers")
            } footer: {
                Text("Auto picks the best installed tool for each kind of task and skips one that is close to its usage limit (from the Usage tab). Private tasks only ever run on this Mac.")
            }
            Section {
                Picker("Coding agent", selection: $codingTool) {
                    ForEach(CodingTool.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Terminal app", selection: $terminalApp) {
                    Text("Automatic").tag("auto")
                    ForEach(TerminalApp.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Coding in a terminal")
            } footer: {
                Text("\"Fix the login bug in Zeus\" opens this terminal in that project and starts the agent on it. The agent runs with its own settings, as in any terminal you open yourself; the model limits above are for Zeus's own answers only.")
            }
            Section("Installed") {
                ForEach(RouterEngine.allCases) { engine in
                    LabeledContent(engine.title) {
                        if let path = settings.installed[engine] {
                            Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).foregroundStyle(.secondary).textSelection(.enabled)
                        } else {
                            Text("Not found").foregroundStyle(.tertiary)
                        }
                    }
                }
                Button("Look Again") { settings.refresh() }
            }
        }
        .formStyle(.grouped)
        .onAppear { settings.refresh() }
    }
}

/// Shared flags between a CLI's output handler, its silence timer and its exit handler.
final class CLIRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var output = false, timeout = false
    private var last = Date()
    var hadOutput: Bool { lock.withLock { output } }
    var timedOut: Bool { lock.withLock { timeout } }
    /// Seconds since the run started or since it last produced output.
    var quietFor: TimeInterval { lock.withLock { Date().timeIntervalSince(last) } }
    func mark(output value: Bool) { lock.withLock { output = value; last = Date() } }
    func mark(timedOut value: Bool) { lock.withLock { timeout = value } }
}

/// The last few KB of a CLI's stderr, kept while it runs so the pipe never fills.
final class BoundedTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit = 16_384
    func append(_ more: Data) {
        guard !more.isEmpty else { return }
        lock.withLock {
            data.append(more)
            if data.count > limit { data = Data(data.suffix(limit)) }
        }
    }
    var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}
