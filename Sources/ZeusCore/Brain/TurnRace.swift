import Foundation

/// Timing budget and tier choice for a "Talk to Zeus" answer. The owner's run of build 0405391 tried
/// four engines one after another with 20 to 30 s silent timeouts and said nothing for 85 s. A turn now
/// starts every fast engine at once, speaks whichever streams first, and gives up after `firstTextBudgetMs`.
public enum FastTier {
    /// No engine has streamed a word by now: say one short in-character line so the room is never silent.
    public static let fillerMs = 900
    /// Hard ceiling for the first word from any engine. Never 30 s.
    public static let firstTextBudgetMs = 8_000
    /// How often the controller feeds the reducer a clock tick.
    public static let tickMs = 100
    /// A deep answer that has not arrived by now is dropped, silently.
    public static let deepBudgetMs = 90_000
    /// The deep follow-up is spoken only while the owner is still in the conversation, this long after the fast answer.
    public static let conversationWindowSeconds: TimeInterval = 45

    /// Engines that can start a voice answer quickly, best first. Direct HTTPS streaming beats spawning a CLI.
    /// Local Ollama joins only when `/api/ps` already lists a loaded model. Gemini, Grok, Cursor and the
    /// Ollama CLI are too slow to start for a spoken answer and stay out of the race.
    public static func fastRace(order: [BrainEngineID], ollamaWarm: Bool, limit: Int = 4) -> [BrainEngineID] {
        let ranking: [BrainEngineID] = [.anthropicAPI, .openAIAPI, .claude, .codex, .ollamaHTTP]
        let picked = ranking.filter { id in
            order.contains(id) && (id != .ollamaHTTP || ollamaWarm)
        }
        return Array(picked.prefix(limit))
    }

    /// The engine for the background deep answer: Sonnet over the API, then the Claude CLI, then a GPT model.
    public static func deepEngine(order: [BrainEngineID]) -> BrainEngineID? {
        [BrainEngineID.anthropicAPI, .claude, .openAIAPI, .codex].first { order.contains($0) }
    }
}

/// Whether a question deserves a second, slower answer after the quick one.
public enum DeepTrigger {
    public enum Reason: String, Sendable, Equatable { case explicit, complexity }

    private static let explicit = ["think harder", "think deeper", "think about it", "think it through", "take your time",
                                   "go deeper", "in depth", "in detail", "deep dive", "reason about"]
    private static let complex = ["explain", "why does", "why do", "how does", "how do i", "compare", "plan", "strategy",
                                  "design", "architecture", "write a", "draft", "summarize", "analyse", "analyze",
                                  "pros and cons", "trade off", "tradeoff", "debug", "code", "implement", "refactor"]

    public static func reason(for transcript: String, task: RouterTask) -> Reason? {
        let text = transcript.lowercased()
        // A private task never leaves this Mac, so it never gets a cloud deep answer.
        if task == .privateLocal { return nil }
        if explicit.contains(where: text.contains) { return .explicit }
        if task == .code || task == .research || task == .longWriting { return .complexity }
        let words = text.split(separator: " ").count
        if words >= 12, complex.contains(where: text.contains) { return .complexity }
        return nil
    }
}

public enum TurnRacePhase: String, Sendable, Equatable {
    case listening, racing, speakingFast, deepPending, done, failed
}

public enum TierStatus: Equatable, Sendable { case running, failed, cancelled, won }

public enum TurnRaceFailure: String, Sendable, Equatable { case timeout, allFailed, noTier }

public enum TurnRaceEvent: Sendable, Equatable {
    /// The key was released. `deep` is the reason a background deep answer is wanted, if any.
    /// `budgetMs` is how long any tier may stay silent: 8 s for a spoken turn, longer for an explicit deep turn.
    case released(tiers: [String], deep: DeepTrigger.Reason?, atMs: Int, budgetMs: Int = FastTier.firstTextBudgetMs)
    case tick(atMs: Int)
    /// A tier streamed its first text.
    case firstText(tier: String, atMs: Int)
    case tierFailed(tier: String, atMs: Int)
    /// The winning tier finished its answer.
    case fastFinished(atMs: Int)
    case deepAnswer(text: String)
    case deepFailed
    /// A new key press, or any cancel.
    case cancelled
}

public enum TurnRaceEffect: Sendable, Equatable {
    case start(tier: String)
    case cancel(tier: String)
    case speakFiller
    case startDeep
    case cancelDeep
    case speakError(TurnRaceFailure)
    /// The fuller answer, to deliver after the fast one has finished.
    case deliverDeep(text: String)
}

/// The turn race as a pure value: no clock, no engines, no speech. The Zeus target feeds it events and runs its effects.
public struct TurnRaceState: Equatable, Sendable {
    public private(set) var phase: TurnRacePhase = .listening
    public private(set) var tiers: [String: TierStatus] = [:]
    public private(set) var winner: String?
    public private(set) var startedAtMs = 0
    public private(set) var budgetMs = FastTier.firstTextBudgetMs
    public private(set) var firstTextAtMs: Int?
    public private(set) var failure: TurnRaceFailure?
    public private(set) var fillerSpoken = false
    public private(set) var deepReason: DeepTrigger.Reason?
    public private(set) var deepRunning = false
    public private(set) var fastFinished = false
    private var heldDeep: String?

    public init() {}

    public var winnerLatencyMs: Int? { firstTextAtMs.map { $0 - startedAtMs } }

    public mutating func reduce(_ event: TurnRaceEvent) -> [TurnRaceEffect] {
        switch event {
        case let .released(ids, deep, now, budget):
            guard phase == .listening else { return [] }
            startedAtMs = now
            budgetMs = budget
            deepReason = deep
            guard !ids.isEmpty else {
                phase = .failed
                failure = .noTier
                return [.speakError(.noTier)]
            }
            phase = .racing
            for id in ids { tiers[id] = .running }
            return ids.map { .start(tier: $0) }

        case let .tick(now):
            guard phase == .racing else { return [] }
            if now - startedAtMs >= budgetMs {
                phase = .failed
                failure = .timeout
                return cancelRunning() + [.speakError(.timeout)]
            }
            if !fillerSpoken, now - startedAtMs >= FastTier.fillerMs {
                fillerSpoken = true
                return [.speakFiller]
            }
            return []

        case let .firstText(tier, now):
            guard tiers[tier] == .running else { return [] }
            guard phase == .racing, winner == nil else {
                // A loser that streams after the winner is told to stop.
                tiers[tier] = .cancelled
                return [.cancel(tier: tier)]
            }
            winner = tier
            firstTextAtMs = now
            phase = .speakingFast
            tiers[tier] = .won
            var effects = cancelRunning()
            if deepReason != nil {
                deepRunning = true
                effects.append(.startDeep)
            }
            return effects

        case let .tierFailed(tier, _):
            guard tiers[tier] == .running || tiers[tier] == .won else { return [] }
            tiers[tier] = .failed
            guard phase == .racing, !tiers.values.contains(.running) else { return [] }
            phase = .failed
            failure = .allFailed
            return [.speakError(.allFailed)]

        case .fastFinished:
            guard phase == .speakingFast else { return [] }
            fastFinished = true
            if deepRunning {
                phase = .deepPending
                if let text = heldDeep {
                    heldDeep = nil
                    phase = .done
                    return [.deliverDeep(text: text)]
                }
            } else {
                phase = .done
            }
            return []

        case let .deepAnswer(text):
            guard deepRunning else { return [] }
            deepRunning = false
            // The fuller answer always arrives after the quick one, never over it.
            if fastFinished {
                phase = .done
                return [.deliverDeep(text: text)]
            }
            heldDeep = text
            deepRunning = true
            return []

        case .deepFailed:
            guard deepRunning else { return [] }
            deepRunning = false
            heldDeep = nil
            if fastFinished, phase == .deepPending { phase = .done }
            return []

        case .cancelled:
            guard phase != .done, phase != .failed else { return [] }
            phase = .done
            var effects = cancelRunning()
            if deepRunning { effects.append(.cancelDeep) }
            deepRunning = false
            heldDeep = nil
            return effects
        }
    }

    private mutating func cancelRunning() -> [TurnRaceEffect] {
        var effects: [TurnRaceEffect] = []
        for (tier, status) in tiers.sorted(by: { $0.key < $1.key }) where status == .running {
            tiers[tier] = .cancelled
            effects.append(.cancel(tier: tier))
        }
        return effects
    }
}
