import Foundation
import os
import ZeusCore

/// Understanding a command quickly: local rules (`FastIntent`, < 2 ms), then Jev (TypeSafe System One,
/// only with a Keychain key and a monthly limit, inside a 600 ms budget), and only then the LLM brain.
/// Whichever stage understood it, `FastActions` carries it out. Jev is never called on a partial
/// transcript. Jev errors and timeouts fail open to the LLM; a low-confidence answer never acts.
@MainActor
final class FastPath {
    static let shared = FastPath()

    enum Result {
        case hit(FastActions.Plan, engine: String)
        case ask(String, engine: String)
        case miss
    }

    let actions: FastActions
    /// Engine answers below this confidence don't act; the LLM takes the request (and can ask).
    var minimumConfidence = 0.7
    /// How long a voice turn waits for Jev before going to the LLM (the router enforces 600 ms itself).
    var engineBudget: Duration = .milliseconds(650)

    static let log = OSLog(subsystem: "app.zeus.mac", category: "fast")
    let signposter = OSSignposter(subsystem: "app.zeus.mac", category: "fast")

    private var partialGate = PartialActionGate()

    init(actions: FastActions = .shared) { self.actions = actions }

    // MARK: Stage 1: rules

    func rules(_ transcript: String) -> Result {
        // Settings › Features › Instant commands: off hands every command to the LLM.
        guard FeatureSettings.fastPathEnabled() else { return .miss }
        let started = ContinuousClock.now
        let intent = FastIntent.parse(transcript)
        let parse = ContinuousClock.now - started
        guard let intent else { return .miss }
        NSLog("[ZEUS] fast: rules matched %@ in %.2fms", intent.intentLabel, Self.ms(parse))
        switch actions.resolve(intent) {
        case .plan(let plan):
            IntelligenceCenter.shared.remember(transcript, decision: intent.decision)
            return .hit(plan, engine: "Rules")
        case .ask(let question):
            return .ask(question, engine: "Rules")
        case .pass:
            return .miss
        }
    }

    // MARK: Stage 2: Jev

    func engine(_ transcript: String) async -> Result {
        guard FeatureSettings.fastPathEnabled() else { return .miss }
        guard FastIntent.mayBeCommand(transcript) else { return .miss }
        let center = IntelligenceCenter.shared
        let started = ContinuousClock.now
        // Never cancelled on timeout: a cancelled Jev call would leave its reservation uncertain.
        let task = Task { @MainActor in await center.decide(transcript, announce: false).decision }
        let decision = await Self.first(task, within: engineBudget) ?? nil
        NSLog("[ZEUS] fast: engine %@ in %.0fms", decision.map { IntelligenceCenter.name($0.source) } ?? "no answer",
              Self.ms(ContinuousClock.now - started))
        guard let decision, let answer = decision.answers["intent"], let label = answer.choice else { return .miss }
        let engine = IntelligenceCenter.name(decision.source)
        guard FastIntent.actionableLabels.contains(label) else { return .miss }
        let confidence = answer.confidence ?? decision.confidence
        guard confidence >= minimumConfidence || decision.source == .rules else {
            NSLog("[ZEUS] fast: %@ said %@ at %.2f, below %.2f: to the LLM", engine, label, confidence, minimumConfidence)
            return .miss
        }
        guard let intent = FastIntent.fromEngine(label: label, utterance: transcript) else {
            NSLog("[ZEUS] fast: %@ said %@ but the details weren't in the words", engine, label)
            return .miss
        }
        switch actions.resolve(intent) {
        case .plan(let plan): return .hit(plan, engine: engine)
        case .ask(let question): return .ask(question, engine: engine)
        case .pass: return .miss
        }
    }

    /// Called with each live partial. Feeds the partial-action gate only; nothing is sent to a model.
    func partial(_ text: String) {
        guard FeatureSettings.fastPathEnabled() else { return }
        partialGate.observePartial(text)
    }

    func reset() {
        partialGate = PartialActionGate()
    }

    // MARK: Helpers

    /// The task's value, or nil if it isn't ready within `limit`. The task keeps running either way.
    static func first<T: Sendable>(_ task: Task<T, Never>, within limit: Duration) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = FastOnceGate()
            Task { let value = await task.value; if gate.open() { continuation.resume(returning: value) } }
            Task { try? await Task.sleep(for: limit); if gate.open() { continuation.resume(returning: nil) } }
        }
    }

    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}

/// Lets exactly one of several racers through.
final class FastOnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func open() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
