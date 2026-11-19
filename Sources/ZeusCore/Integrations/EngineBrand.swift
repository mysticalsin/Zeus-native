import Foundation

/// Which engine mark to show. One table in ZeusCore; views load `assetName` from the Zeus bundle only.
public enum EngineBrandMark: String, CaseIterable, Sendable, Equatable {
    case cursor
    case openai
    case claude
    case anthropic
    case gemini
    case kimi
    case grok
    case ollama
    case lmStudio
    /// Unknown engines without a verified provider mark.
    case fallback

    /// Vector asset base name under `Integrations/Brands/` (no extension).
    public var assetName: String {
        switch self {
        case .cursor: "engine-cursor"
        case .openai: "engine-openai"
        case .claude: "engine-claude"
        case .anthropic: "engine-anthropic"
        case .gemini: "engine-gemini"
        case .kimi: "engine-kimi"
        case .grok: "engine-grok"
        case .ollama: "engine-ollama"
        case .lmStudio: "engine-lmstudio"
        case .fallback: "engine-fallback"
        }
    }

    public var assetExtension: String {
        switch self {
        case .grok, .ollama, .lmStudio: "svg"
        default: "pdf"
        }
    }

    public var title: String {
        switch self {
        case .cursor: "Cursor"
        case .openai: "OpenAI"
        case .claude: "Claude"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        case .kimi: "Kimi"
        case .grok: "Grok"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .fallback: "Unknown engine"
        }
    }
}

/// Maps agent names, engine ids and aliases to a single logo (case-insensitive).
public enum EngineBrand {
    /// Every alias that must resolve to `mark` in tests.
    public static let aliasSamples: [(String, EngineBrandMark)] = [
        ("cursor", .cursor), ("Cursor Agent", .cursor), ("cursor-agent", .cursor), ("composer", .cursor),
        ("openai", .openai), ("chatgpt", .openai), ("ChatGPT", .openai), ("codex", .openai), ("Codex", .openai),
        ("gpt-4o", .openai), ("gpt 4", .openai),
        ("claude", .claude), ("Claude Code", .claude), ("claude-code", .claude),
        ("anthropic", .anthropic), ("Anthropic", .anthropic),
        ("gemini", .gemini), ("Gemini", .gemini), ("googlegemini", .gemini),
        ("kimi", .kimi), ("Kimi", .kimi), ("moonshot", .kimi), ("moonshotai", .kimi),
        ("grok", .grok), ("Grok", .grok), ("Grok Bot", .grok), ("xai", .grok), ("xAI", .grok), ("x.ai", .grok),
        ("ollama", .ollama), ("Ollama (local)", .ollama), ("LM Studio", .lmStudio), ("lmstudio", .lmStudio),
        ("totally-unknown-engine", .fallback),
    ]

    /// Agent row labels and engine ids from hooks, settings and the router.
    public static func resolve(_ raw: String) -> EngineBrandMark {
        let key = normalize(raw)
        guard !key.isEmpty else { return EngineBrandMark.fallback }
        if key.hasPrefix("gpt-") || key.hasPrefix("gpt ") || key == "gpt" {
            return EngineBrandMark.openai
        }
        switch key {
        case "cursor", "cursor agent", "cursor agent cli", "cursor cli", "cursor-agent", "composer":
            return EngineBrandMark.cursor
        case "openai", "chatgpt", "codex", "codex cli":
            return EngineBrandMark.openai
        case "claude", "claude code", "claudecode", "cloud code":
            return EngineBrandMark.claude
        case "anthropic":
            return EngineBrandMark.anthropic
        case "gemini", "gemini cli", "googlegemini", "jemini":
            return EngineBrandMark.gemini
        case "kimi", "moonshot", "moonshotai", "moonshot ai":
            return EngineBrandMark.kimi
        case "grok", "grok bot", "xai", "x ai":
            return EngineBrandMark.grok
        case "ollama", "ollama local":
            return EngineBrandMark.ollama
        case "lm studio", "lmstudio":
            return EngineBrandMark.lmStudio
        default:
            return EngineBrandMark.fallback
        }
    }

    public static func resolve(provider: AIProvider) -> EngineBrandMark {
        switch provider {
        case .claudeCode: return EngineBrandMark.claude
        case .codex, .chatgpt: return EngineBrandMark.openai
        case .cursor: return EngineBrandMark.cursor
        case .gemini: return EngineBrandMark.gemini
        case .grok: return EngineBrandMark.grok
        case .ollama: return EngineBrandMark.ollama
        case .lmStudio: return EngineBrandMark.lmStudio
        case .anyLLM: return EngineBrandMark.fallback
        }
    }

    public static func resolve(engine: RouterEngine) -> EngineBrandMark {
        switch engine {
        case .claude: return EngineBrandMark.claude
        case .codex: return EngineBrandMark.openai
        case .gemini: return EngineBrandMark.gemini
        case .cursorAgent: return EngineBrandMark.cursor
        case .grok: return EngineBrandMark.grok
        case .ollama: return EngineBrandMark.ollama
        }
    }

    public static func resolve(tool: CodingTool) -> EngineBrandMark {
        switch tool {
        case .claude: return EngineBrandMark.claude
        case .codex: return EngineBrandMark.openai
        case .gemini: return EngineBrandMark.gemini
        case .cursorAgent: return EngineBrandMark.cursor
        }
    }

    /// Labels for silent E2E and snapshot renders: one row per distinct mark plus unknown.
    public static let debugSampleAgents: [String] = [
        "Cursor Agent", "ChatGPT", "Codex", "Claude Code", "Anthropic", "Gemini", "Kimi", "Grok", "Ollama", "LM Studio", "some-unknown-cli",
    ]

    private static func normalize(_ text: String) -> String {
        AppMatcher.normalize(text)
    }
}
