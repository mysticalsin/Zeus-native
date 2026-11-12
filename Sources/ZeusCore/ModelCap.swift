import Foundation

/// How hard a turn needs to think. Quick turns (commands, short answers) take the small model; deep
/// turns (planning, long writing) take the mid-size one, and never anything larger.
public enum ModelTier: String, Sendable {
    case fast, deep
}

/// Tony's rule: ZEUS acts with Haiku, or Sonnet at most, and the same size on every other engine.
/// Every CLI launch passes an explicit model (or effort) from here, so a CLI's own default (often
/// its largest model at maximum effort) is never used. Overrides live in UserDefaults
/// (`modelCap.<engine>.<tier>`) for when a provider renames its models; `isAllowed` still applies.
public enum ModelCap {
    /// Model names per engine and tier. Codex has no small/medium model name that is stable across
    /// accounts, so it keeps the account's model and caps the reasoning effort instead.
    static let defaults: [RouterEngine: [ModelTier: String]] = [
        .claude: [.fast: "haiku", .deep: "sonnet"],
        .gemini: [.fast: "gemini-3.7-flash", .deep: "gemini-3.7-flash"],
        .cursorAgent: [.fast: "gemini-3.7-flash-high", .deep: "claude-sonnet-5-thinking-high"],
    ]
    /// The smallest GPT model in Codex's own model list (`gpt-6-luna`, seen in `~/.codex/models_cache.json`).
    /// A spoken turn pins it so the account default (a larger model on priority tier) is never used.
    /// Override with `modelCap.codex.fast` when a provider renames it.
    public static let codexVoiceModel = "gpt-6-luna"

    static let codexEffort: [ModelTier: String] = [.fast: "low", .deep: "medium"]

    public static func model(for engine: RouterEngine, tier: ModelTier, defaults store: UserDefaults = .standard) -> String? {
        if let override = store.string(forKey: "modelCap.\(engine.rawValue).\(tier.rawValue)"),
           !override.isEmpty, isAllowed(override) {
            return override
        }
        return defaults[engine]?[tier]
    }

    /// The flags that pin the model (or effort) for one launch of `engine`.
    public static func arguments(for engine: RouterEngine, tier: ModelTier, defaults store: UserDefaults = .standard) -> [String] {
        switch engine {
        case .claude, .cursorAgent:
            return model(for: engine, tier: tier, defaults: store).map { ["--model", $0] } ?? []
        case .gemini:
            return model(for: engine, tier: tier, defaults: store).map { ["-m", $0] } ?? []
        case .codex:
            var flags = ["-c", "model_reasoning_effort=\"\(codexEffort[tier] ?? "low")\""]
            if let override = store.string(forKey: "modelCap.codex.\(tier.rawValue)"), !override.isEmpty, isAllowed(override) {
                flags += ["-m", override]
            }
            return flags
        case .grok, .ollama:
            return [] // Grok CLI has no model flag here; Ollama runs Tony's chosen local model.
        }
    }

    /// The model (or effort) each tier uses on `engine`, for Settings' read-only display.
    public static func describe(_ engine: RouterEngine, defaults store: UserDefaults = .standard) -> (fast: String, deep: String) {
        func text(_ tier: ModelTier) -> String {
            switch engine {
            case .codex:
                let override = store.string(forKey: "modelCap.codex.\(tier.rawValue)").flatMap { $0.isEmpty || !isAllowed($0) ? nil : $0 }
                return (override ?? "your account's model") + ", \(codexEffort[tier] ?? "low") effort"
            case .grok: return "its own default (no model flag)"
            case .ollama: return "the local model you chose"
            default: return model(for: engine, tier: tier, defaults: store) ?? "its default"
            }
        }
        return (text(.fast), text(.deep))
    }

    /// Words that mark a model larger than Sonnet (or an effort above medium). Any model name
    /// containing one is refused, wherever it comes from.
    static let tooLarge = ["opus", "fable", "-pro", "ultra", "xhigh", "-max", "astra", "o1-pro", "o3-pro"]

    public static func isAllowed(_ model: String) -> Bool {
        let name = model.lowercased()
        return !tooLarge.contains { name.contains($0) }
    }

    /// HTTP brains (Ollama, Anthropic, OpenAI). A name larger than Sonnet is refused.
    public enum HTTPPreset: String, Sendable { case ollama, anthropic, openAI }

    public static func httpModel(_ preset: HTTPPreset, tier: ModelTier) -> String? {
        let name: String = switch (preset, tier) {
        case (.ollama, _): "llama3.2"
        case (.anthropic, .fast): "claude-haiku-5-5"
        case (.anthropic, .deep): "claude-sonnet-4-5"
        case (.openAI, .fast): "gpt-4o-mini"
        case (.openAI, .deep): "gpt-4o"
        }
        // A provider renames its models: `modelCap.<preset>.<tier>` in UserDefaults wins while it stays inside the cap.
        if let override = UserDefaults.standard.string(forKey: "modelCap.http.\(preset.rawValue).\(tier.rawValue)"),
           !override.isEmpty, isAllowed(override) {
            return override
        }
        return isAllowed(name) ? name : nil
    }

    /// The name a caller wants to send, or nil when it is over the cap.
    public static func gatedHTTPModel(_ name: String) -> String? {
        isAllowed(name) ? name : nil
    }
}
