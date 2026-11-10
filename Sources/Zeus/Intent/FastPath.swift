import Foundation
import os
import ZeusCore

/// Understanding a command quickly, in Tony's order: local rules (`FastIntent`, < 2 ms), then
/// the decision engine (Laya on this Mac, Jev in the cloud only when Settings allows, inside the
/// cap), and only then the LLM brain. Whichever stage understood it, `FastActions` carries it out.
///
/// While you speak, partial transcripts that stay unchanged for 200 ms are parsed ahead of time
/// and, when allowed, sent to Laya, so the answer is often ready when the final transcript lands
/// (idea from jev-voice-browser, MIT). Stale speculations are simply ignored, never cancelled
/// mid-request. Jev errors fail open to the LLM; a low-confidence answer never acts, and Tony's
/// Engine choice is never overridden (ideas from jev-router, MIT).
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
    /// How long a voice turn waits for Laya or Jev before going to the LLM.
    var engineBudget: Duration = .milliseconds(1200)

    static let log = OSLog(subsystem: "app.zeus.mac", category: "fast")
    let signposter = OSSignposter(subsystem: "app.zeus.mac", category: "fast")

    private var debounce: Task<Void, Never>?
    private var speculation: (key: String, task: Task<Decision?, Never>)?
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

    // MARK: Stage 2: Laya / Jev

    func engine(_ transcript: String) async -> Result {
        guard FeatureSettings.fastPathEnabled() else { return .miss }
        guard FastIntent.mayBeCommand(transcript) else { return .miss }
        let center = IntelligenceCenter.shared
        let key = FastIntent.key(transcript)
        var decision: Decision?
        // A speculative Laya answer for this exact text is reused when it is decisive enough.
        if let speculation, speculation.key == key {
            self.speculation = nil
            if let early = await Self.first(speculation.task, within: .milliseconds(400)) ?? nil,
               center.engine == .laya || early.confidence >= IntelligenceCenter.confidenceFloor {
                center.remember(transcript, decision: early)
                decision = early
                NSLog("[ZEUS] fast: reused speculative Laya answer")
            }
        }
        if decision == nil {
            let started = ContinuousClock.now
            // Never cancelled on timeout: a cancelled Jev call would leave its reservation uncertain.
            let task = Task { @MainActor in await center.decide(transcript, announce: false).decision }
            decision = await Self.first(task, within: engineBudget) ?? nil
            NSLog("[ZEUS] fast: engine %@ in %.0fms", decision.map { IntelligenceCenter.name($0.source) } ?? "no answer",
                  Self.ms(ContinuousClock.now - started))
        }
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

    // MARK: Speculation on partial transcripts

    /// Called with each live partial. After 200 ms without change, warms up the answer.
    func partial(_ text: String) {
        guard FeatureSettings.fastPathEnabled() else { return }
        partialGate.observePartial(text)
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            self.speculate(text)
        }
    }

    private func speculate(_ text: String) {
        // Rules need no warming (they take microseconds). Only send what the rules miss.
        guard FastIntent.parse(text) == nil, FastIntent.mayBeCommand(text), IntelligenceCenter.shared.speculates else { return }
        let key = FastIntent.key(text)
        guard speculation?.key != key else { return }
        speculation = (key, Task { @MainActor in await IntelligenceCenter.shared.layaOnly(text) })
    }

    func reset() {
        debounce?.cancel()
        debounce = nil
        speculation = nil
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
