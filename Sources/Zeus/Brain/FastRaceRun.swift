import Foundation
import ZeusCore

/// Drives one spoken answer: every fast engine starts at once, the first to stream text wins and the
/// rest are stopped, and an optional deep engine answers in the background. All decisions come from the
/// pure `TurnRaceState` reducer; this class only starts engines, keeps the clock and runs the effects.
@MainActor
final class FastRaceRun {
    struct Tier {
        let id: String
        let provider: BrainProvider
    }

    struct Callbacks {
        /// A short in-character line for a slow start (at 900 ms with nothing streamed).
        var filler: () -> Void
        /// A tier failed before or without winning; the owner of the turn records quota, sign-in and timeout state.
        var tierFailed: (_ id: String, _ message: String) -> Void
        /// Text from the winner arrived (first call logs the first-token timing).
        var firstText: (_ id: String, _ milliseconds: Int) -> Void
        /// The deep answer, ready after the fast one has finished.
        var deliverDeep: (_ text: String) -> Void
    }

    private enum Message: Sendable {
        case text(String, String)
        case finished(String)
        case failed(String, String)
        case tick
    }

    private var state = TurnRaceState()
    private let tiers: [Tier]
    private let request: BrainRequest
    private let deepTier: Tier?
    private let deepReason: DeepTrigger.Reason?
    private let callbacks: Callbacks
    private let started = ContinuousClock.now
    private var tasks: [String: Task<Void, Never>] = [:]
    private var turns: [String: UUID] = [:]
    private var deepTask: Task<Void, Never>?
    private var deepTurn: UUID?
    private var errors: [String] = []
    private var ticker: Task<Void, Never>?

    var winnerID: String? { state.winner }
    var phase: TurnRacePhase { state.phase }

    init(tiers: [Tier], request: BrainRequest, deepTier: Tier?, deepReason: DeepTrigger.Reason?, callbacks: Callbacks) {
        var seen = Set<String>()
        self.tiers = tiers.filter { seen.insert($0.id).inserted } // one slot per id
        self.request = request
        self.deepTier = deepTier
        self.deepReason = deepTier == nil ? nil : deepReason
        self.callbacks = callbacks
    }

    private func elapsedMs() -> Int {
        let duration = ContinuousClock.now - started
        return Int(duration.components.seconds) * 1000 + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    /// Streams the winner's text through `onDelta`. Throws when no tier answers (all failed, or silent past 8 s).
    func run(onDelta: (String) -> Void) async throws {
        let (channel, sink) = AsyncStream<Message>.makeStream()
        var fatal: Error?
        func apply(_ event: TurnRaceEvent) {
            for effect in state.reduce(event) {
                switch effect {
                case .start(let id):
                    guard let tier = tiers.first(where: { $0.id == id }) else { continue }
                    let turn = UUID()
                    turns[id] = turn
                    let tierRequest = request.with(turn: turn)
                    tasks[id] = Task.detached {
                        do {
                            for try await brainEvent in tier.provider.send(tierRequest) {
                                if case .textDelta(let text) = brainEvent, !text.isEmpty { sink.yield(.text(id, text)) }
                            }
                            sink.yield(.finished(id))
                        } catch {
                            sink.yield(.failed(id, error.localizedDescription))
                        }
                    }
                case .cancel(let id):
                    stop(id)
                case .speakFiller:
                    callbacks.filler()
                case .startDeep:
                    startDeep()
                case .cancelDeep:
                    stopDeep()
                case .speakError(let failure):
                    fatal = failure == .timeout
                        ? ClaudeCLIProvider.ProviderError.failed("No AI answered in time")
                        : ClaudeCLIProvider.ProviderError.failed(VoiceTurnController.allEnginesFailed(errors))
                case .deliverDeep(let text):
                    callbacks.deliverDeep(text)
                }
            }
        }

        ticker = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(FastTier.tickMs))
                sink.yield(.tick)
            }
        }
        defer {
            ticker?.cancel()
            for id in tasks.keys { stop(id) }
            sink.finish()
        }

        apply(.released(tiers: tiers.map(\.id), deep: deepReason, atMs: 0,
                        budgetMs: Int((request.firstTextBudget ?? Double(FastTier.firstTextBudgetMs) / 1000) * 1000)))
        if let fatal { throw fatal }

        for await message in channel {
            if Task.isCancelled { break }
            switch message {
            case .text(let id, let text):
                if state.winner == nil {
                    apply(.firstText(tier: id, atMs: elapsedMs()))
                    if state.winner == id { callbacks.firstText(id, state.winnerLatencyMs ?? 0) }
                }
                if state.winner == id { onDelta(text) }
            case .finished(let id):
                if state.winner == id {
                    apply(.fastFinished(atMs: elapsedMs()))
                    return
                }
                // An engine that ends with no text is a failure, not a win.
                apply(.tierFailed(tier: id, atMs: elapsedMs()))
                errors.append("\(id) gave no answer")
            case .failed(let id, let text):
                let wasWinner = state.winner == id
                errors.append(text)
                callbacks.tierFailed(id, text)
                apply(.tierFailed(tier: id, atMs: elapsedMs()))
                if wasWinner { throw ClaudeCLIProvider.ProviderError.failed(text) }
            case .tick:
                apply(.tick(atMs: elapsedMs()))
            }
            if let fatal { throw fatal }
        }
        if Task.isCancelled {
            _ = state.reduce(.cancelled)
            throw CancellationError()
        }
    }

    /// A new key press or a stop: nothing from this run may speak after this.
    func cancel() {
        for effect in state.reduce(.cancelled) {
            switch effect {
            case .cancel(let id): stop(id)
            case .cancelDeep: stopDeep()
            default: break
            }
        }
        for id in tasks.keys { stop(id) }
        ticker?.cancel()
        stopDeep()
    }

    private func stop(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        guard let turn = turns.removeValue(forKey: id), let provider = tiers.first(where: { $0.id == id })?.provider else { return }
        Task { await provider.cancel(turn: turn) }
    }

    // MARK: Deep tier

    private func startDeep() {
        guard let deepTier, deepTask == nil else { return }
        let turn = UUID()
        deepTurn = turn
        let deepRequest = request.with(
            turn: turn,
            systemPrompt: request.systemPrompt + """


            The owner already heard a quick answer a moment ago. Now give the fuller, considered answer: \
            at most five short spoken sentences, plain text, no lists, no markdown, and do not repeat the quick answer.
            """,
            deep: true, firstTextBudget: 45)
        let budget = Duration.milliseconds(FastTier.deepBudgetMs)
        let work = Task { [weak self] in
            var text = ""
            do {
                for try await event in deepTier.provider.send(deepRequest) {
                    if case .textDelta(let delta) = event { text += delta }
                }
                self?.deepFinished(text)
            } catch {
                self?.deepFailed()
            }
        }
        deepTask = work
        Task { [weak self] in
            try? await Task.sleep(for: budget)
            guard let self, self.deepTask != nil else { return }
            self.stopDeep()
        }
    }

    private func deepFinished(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { deepFailed(); return }
        deepTask = nil
        for effect in state.reduce(.deepAnswer(text: clean)) {
            if case .deliverDeep(let answer) = effect { callbacks.deliverDeep(answer) }
        }
    }

    private func deepFailed() {
        deepTask = nil
        _ = state.reduce(.deepFailed)
    }

    private func stopDeep() {
        deepTask?.cancel()
        deepTask = nil
        if let turn = deepTurn, let provider = deepTier?.provider {
            deepTurn = nil
            Task { await provider.cancel(turn: turn) }
        }
        _ = state.reduce(.deepFailed)
    }

    /// Called when the fast answer reached its end without `run` being the one to see it (replay path).
    func fastDone() {
        for effect in state.reduce(.fastFinished(atMs: elapsedMs())) {
            if case .deliverDeep(let answer) = effect { callbacks.deliverDeep(answer) }
        }
    }
}
