import Foundation

/// The command line AIs ZEUS can hand a task to.
public enum RouterEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude, codex, gemini, cursorAgent, grok, ollama

    public var id: String { rawValue }

    public var binary: String {
        switch self {
        case .cursorAgent: "cursor-agent"
        default: rawValue
        }
    }

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .cursorAgent: "Cursor Agent"
        case .grok: "Grok"
        case .ollama: "Ollama (local)"
        }
    }

    /// Runs on this Mac; nothing leaves it.
    public var isLocal: Bool { self == .ollama }

    /// Arguments for a one-shot, non-interactive answer that prints plain text. Claude has its
    /// own streaming provider and is not run through these.
    /// Every launch is pinned to ModelCap's tier: Haiku/Sonnet size at most, never a CLI's default.
    public func headlessArguments(prompt: String, localModel: String = "llama3.2", tier: ModelTier = .fast) -> [String] {
        let cap = ModelCap.arguments(for: self, tier: tier)
        return switch self {
        case .claude: cap + ["-p", prompt]
        case .codex: ["exec", "--skip-git-repo-check"] + cap + [prompt]
        case .gemini: cap + ["-p", prompt]
        case .cursorAgent: cap + ["--trust", "-p", prompt, "--output-format", "text"] // trust = Zeus's own empty run folder only; never --force
        case .grok: ["-p", prompt]
        case .ollama: ["run", localModel, prompt]
        }
    }

    /// Finds installed engines by looking for executables only; nothing is run, so no paid call
    /// can happen during detection.
    public static func installed(searchDirectories: [String], extraPaths: [RouterEngine: [String]] = [:],
                                 isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) })
        -> [RouterEngine: String] {
        var found: [RouterEngine: String] = [:]
        for engine in allCases {
            let candidates = searchDirectories.map { "\($0)/\(engine.binary)" } + (extraPaths[engine] ?? [])
            if let path = candidates.first(where: isExecutable) { found[engine] = path }
        }
        return found
    }
}

/// The kinds of task the router tells apart.
public enum RouterTask: String, CaseIterable, Codable, Identifiable, Sendable {
    case code, research, quickAnswer, longWriting, privateLocal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .code: "Code"
        case .research: "Research"
        case .quickAnswer: "Quick answers"
        case .longWriting: "Long writing"
        case .privateLocal: "Private (stays on this Mac)"
        }
    }

    /// Best engine first.
    public var ranking: [RouterEngine] {
        switch self {
        case .code: [.claude, .codex, .cursorAgent, .gemini, .grok, .ollama]
        case .research: [.gemini, .claude, .grok, .codex]
        case .quickAnswer: [.claude, .gemini, .grok, .ollama, .codex]
        case .longWriting: [.claude, .gemini, .grok, .codex]
        // Private work never goes to a cloud engine.
        case .privateLocal: [.ollama]
        }
    }

    /// A light guess from the wording. Explicit privacy words win, then code, research and
    /// writing cues; anything short is a quick answer.
    public static func classify(_ prompt: String) -> RouterTask {
        let text = prompt.lowercased()
        let words = text.split { !$0.isLetter && !$0.isNumber && $0 != "`" }.map(String.init)
        func has(_ cues: [String]) -> Bool { cues.contains { cue in cue.contains(" ") ? text.contains(cue) : words.contains(cue) } }
        if has(["private", "privately", "offline", "locally", "confidential", "on device", "don't upload", "do not upload"]) {
            return .privateLocal
        }
        if text.contains("```") || has(["code", "function", "bug", "compile", "refactor", "swift", "python", "typescript",
                                         "javascript", "regex", "stack trace", "unit test", "error:", "git", "repo", "api"]) {
            return .code
        }
        if has(["research", "compare", "sources", "latest", "news", "find out", "look up", "investigate", "market", "study"]) {
            return .research
        }
        if has(["essay", "article", "blog", "draft", "write up", "report", "chapter", "story", "speech", "newsletter"])
            || words.count > 60 {
            return .longWriting
        }
        return .quickAnswer
    }
}

/// "Auto", or a fixed engine, per task (Settings › Intelligence).
public enum RouterChoice: Codable, Hashable, Sendable {
    case auto
    case engine(RouterEngine)

    public var storageValue: String {
        switch self {
        case .auto: "auto"
        case .engine(let engine): engine.rawValue
        }
    }

    public init(storageValue: String?) {
        self = storageValue.flatMap(RouterEngine.init(rawValue:)).map(RouterChoice.engine) ?? .auto
    }
}

public struct RouterDecision: Equatable, Sendable {
    public var task: RouterTask
    public var engine: RouterEngine?
    /// One line for the badge's tooltip ("Code → Codex: Claude is at 93% of its 5-hour limit").
    public var reason: String
    public var skipped: [RouterEngine: String]
}

/// Picks the engine for a task: the person's override if it can run, else the best installed
/// engine for the task that is not close to its usage limit.
public enum ModelRouter {
    /// Above this share of a limit an engine is skipped while others can take the task.
    public static let nearLimit = 0.9

    /// Voice turns after the HTTP brains, fastest first. Cursor Agent prints only at the end, so it is last.
    public static let voiceOrder: [RouterEngine] = [.codex, .gemini, .claude, .ollama, .grok, .cursorAgent]

    public static func route(task: RouterTask, installed: Set<RouterEngine>, usage: [RouterEngine: Double] = [:],
                             choice: RouterChoice = .auto) -> RouterDecision {
        var skipped: [RouterEngine: String] = [:]
        func usable(_ engine: RouterEngine) -> Bool {
            guard installed.contains(engine) else { skipped[engine] = "not installed"; return false }
            if task == .privateLocal, !engine.isLocal { skipped[engine] = "not local"; return false }
            if let used = usage[engine], used >= nearLimit {
                skipped[engine] = "at \(Int((used * 100).rounded()))% of its limit"
                return false
            }
            return true
        }

        if case .engine(let chosen) = choice {
            if usable(chosen) {
                return RouterDecision(task: task, engine: chosen, reason: "\(task.title) → \(chosen.title) (your choice)", skipped: skipped)
            }
        }
        for engine in task.ranking where usable(engine) {
            let note = skipped.isEmpty ? "best installed for \(task.title.lowercased())"
                : skipped.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.title) \($0.value)" }.joined(separator: "; ")
            return RouterDecision(task: task, engine: engine, reason: "\(task.title) → \(engine.title): \(note)", skipped: skipped)
        }
        // Everything near its limit: rather than refuse, use the least-used installed engine
        // (never a cloud one for private tasks).
        let fallback = task.ranking.filter { installed.contains($0) && (task != .privateLocal || $0.isLocal) }
            .min { (usage[$0] ?? 0) < (usage[$1] ?? 0) }
        if let fallback {
            return RouterDecision(task: task, engine: fallback, reason: "\(task.title) → \(fallback.title): every engine is near its limit", skipped: skipped)
        }
        let why = task == .privateLocal ? "Install Ollama to keep private tasks on this Mac." : "No AI command line tool is installed."
        return RouterDecision(task: task, engine: nil, reason: why, skipped: skipped)
    }

    /// Limit use per engine from the Usage tab (the fullest meter of each provider).
    public static func usage(from providers: [ProviderUsage]) -> [RouterEngine: Double] {
        var result: [RouterEngine: Double] = [:]
        for provider in providers {
            guard let fraction = provider.tightest?.fraction else { continue }
            switch provider.provider {
            case .claude: result[.claude] = fraction
            case .codex: result[.codex] = fraction
            }
        }
        return result
    }
}
