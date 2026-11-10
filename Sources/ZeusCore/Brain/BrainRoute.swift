import Foundation

/// Which brain may answer a voice turn, fastest first.
public enum BrainEngineID: String, Sendable, Equatable, CaseIterable {
    case ollamaHTTP
    case anthropicAPI
    case openAIAPI
    case codex
    case gemini
    case claude
    case ollama
    case grok
    case cursorAgent
}

/// Order, budget, and escalation for a voice turn. Local and cheap unless the task needs more.
public enum BrainRoute {
    /// Healthy engines in the order a voice turn should try them.
    /// Ollama's HTTP server is always offered: it is on this Mac and costs nothing. A missing server fails fast and the next engine answers.
    public static func order(hasAnthropicKey: Bool, hasOpenAIKey: Bool, installed: Set<RouterEngine>, exhausted: Set<RouterEngine>) -> [BrainEngineID] {
        var result: [BrainEngineID] = [.ollamaHTTP]
        if hasAnthropicKey { result.append(.anthropicAPI) }
        if hasOpenAIKey { result.append(.openAIAPI) }
        let cli: [(RouterEngine, BrainEngineID)] = [
            (.codex, .codex), (.gemini, .gemini), (.claude, .claude), (.ollama, .ollama), (.grok, .grok), (.cursorAgent, .cursorAgent),
        ]
        for (engine, id) in cli where installed.contains(engine) && !exhausted.contains(engine) {
            result.append(id)
        }
        return result
    }

    /// The two fastest, which a turn races. One when nothing else is healthy.
    public static func racePair(hasAnthropicKey: Bool, hasOpenAIKey: Bool, installed: Set<RouterEngine>, exhausted: Set<RouterEngine>) -> [BrainEngineID] {
        Array(order(hasAnthropicKey: hasAnthropicKey, hasOpenAIKey: hasOpenAIKey, installed: installed, exhausted: exhausted).prefix(2))
    }
}

/// Cheap by default. A deeper model is only for a failed attempt or a multi-step task.
public enum ModelBudget {
    public static let medianCostCeiling = 0.002
    public static let medianLatencyCeilingMs = 6_000
    public static let promptCharacterLimit = 10_000

    public struct Sample: Equatable, Sendable {
        public var latencyMs: Int
        public var cost: Double
        public init(latencyMs: Int, cost: Double) {
            self.latencyMs = latencyMs
            self.cost = cost
        }
    }

    /// Fifty cheap-path turns: local or a small model. The budget test reads this fixture, not a live bill.
    public static let cheapFixture: [Sample] = (0..<50).map { index in
        Sample(latencyMs: 180 + (index % 7) * 40, cost: 0.0004 + Double(index % 5) * 0.0001)
    }

    public static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) { return (sorted[mid - 1] + sorted[mid]) / 2 }
        return sorted[mid]
    }

    public static func withinBudget(_ samples: [Sample]) -> Bool {
        guard !samples.isEmpty else { return false }
        let latency = median(samples.map { Double($0.latencyMs) })
        let cost = median(samples.map(\.cost))
        return latency <= Double(medianLatencyCeilingMs) && cost <= medianCostCeiling
    }

    /// Code, research, and long writing are multi-step. A thrown attempt is a failure. Everything else stays on the fast tier.
    public static func shouldEscalate(task: RouterTask, failed: Bool) -> Bool {
        if failed { return true }
        switch task {
        case .code, .research, .longWriting: return true
        case .quickAnswer, .privateLocal: return false
        }
    }

    public static func tier(task: RouterTask, failed: Bool, requestedDeep: Bool) -> ModelTier {
        shouldEscalate(task: task, failed: failed) || requestedDeep ? .deep : .fast
    }

    public static func promptFits(_ prompt: String) -> Bool {
        prompt.count <= promptCharacterLimit
    }
}

/// A brain that has already been started while the person is still talking.
/// A revision throws the previous run away. Nothing here opens an app, speaks, or writes.
public struct AheadBrain: Equatable, Sendable {
    public static let pauseMs: Double = 700

    public private(set) var generation = 0
    public private(set) var armed = ""
    public private(set) var dropped = 0
    /// Stays zero. Speculative work must not act.
    public private(set) var sideEffects = 0

    public enum Effect: Equatable, Sendable {
        case ignore
        case wait
        case start(Int)
        case dropAndStart(Int)
    }

    public init() {}

    public mutating func consider(_ text: String) -> Effect {
        if !Self.canStart(text) {
            if generation > 0 { dropped += 1 }
            generation = 0
            armed = ""
            return .ignore
        }
        let key = FastIntent.key(text)
        if key.isEmpty { return .ignore }
        if key == armed, generation > 0 { return .wait }
        if generation > 0 {
            dropped += 1
            generation += 1
            armed = key
            return .dropAndStart(generation)
        }
        generation = 1
        armed = key
        return .start(generation)
    }

    public func matches(_ text: String) -> Bool {
        generation > 0 && FastIntent.key(text) == armed
    }

    public mutating func discard() {
        if generation > 0 { dropped += 1 }
        generation = 0
        armed = ""
    }

    /// Questions can start early. Commands, page reads, and "on screen" stay put so a dropped run cannot act or answer the wrong picture.
    public static func canStart(_ text: String) -> Bool {
        switch InstantTable.route(text) {
        case .brain, .web:
            let key = FastIntent.key(text)
            let screen = ["on screen", "this screen", "looking at", "over there", "this button", "this window"]
            return !screen.contains { key.contains($0) }
        default:
            return false
        }
    }
}

/// `--strict-mcp-config` keeps a voice turn off the person's own MCP servers. Only pass it when `claude --help` lists it.
public enum ClaudeLaunch {
    public static func supportsStrictMCP(_ help: String) -> Bool {
        help.contains("--strict-mcp-config")
    }
}

/// Whether a warm ping is due. The ping itself stays on the local server.
public enum BrainWarmth {
    public static let interval: TimeInterval = 30 * 60

    public static func due(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
