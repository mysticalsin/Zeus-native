import Foundation
import Observation
import ZeusCore

/// The decision engine for commands: local rules, then Jev in the cloud (needs a key and a monthly
/// cap, inside the local estimate cap), then Ollama last when it is already running. Provider billing remains authoritative.
/// Every answer is kept in a short history tagged with
/// the engine that made it, so Settings > Intelligence can show it and offer "Try with Jev".
@MainActor
@Observable
final class IntelligenceCenter {
    static let shared = IntelligenceCenter()

    struct Record: Identifiable, Equatable {
        let id = UUID()
        let utterance: String
        let at: Date
        var decision: Decision?
        var engineName: String { decision.map { IntelligenceCenter.name($0.source) } ?? "None" }
        var intent: String { decision?.answers["intent"]?.choice ?? "not understood" }
    }

    private(set) var history: [Record] = []
    private(set) var budgetSummary = "Jev off (no monthly estimate cap set)"
    private(set) var jevReservationStatus: JevBudgetStore.ReservationStatus = .clear
    private(set) var localCount = 0
    /// The last Jev key or reconcile failure, shown on the Engine page.
    private(set) var jevMessage: String?
    var onDecided: ((String, String) -> Void)?

    private let budgetStore: JevBudgetStore
    private let testMode: Bool
    private var jev: JevGuard

    private init() {
        let store = JevBudgetStore()
        budgetStore = store
        testMode = false
        // A retired engine choice saved by an older build now means Jev, the only engine.
        IntelligenceEngine.migrateStoredChoice(in: .standard)
        let key = JevKey.load(from: Keychain.store)
        jev = JevGuard(key: key, store: store)
        hasJevKey = key != nil
        Task { await refreshBudget() }
    }

    #if DEBUG
    /// A synthetic profile for exercising the production Engine page. It has no credentials,
    /// provider clients, shared preferences, or on-disk ledger.
    static func isolatedSettingsTestCenter() -> IntelligenceCenter {
        let store = JevBudgetStore.inMemoryForTesting()
        precondition(store.seedReconciliationFixtureForTesting(), "The Jev test fixture requires a volatile-only store")
        return IntelligenceCenter(testStore: store)
    }

    private init(testStore: JevBudgetStore) {
        budgetStore = testStore
        testMode = true
        jev = JevGuard(key: nil, store: testStore)
        Task { await refreshBudget() }
    }
    #endif

    /// Whether a Jev key is saved. Stored, not computed: the Engine page asks on every render, and each ask
    /// used to go through the Keychain store (its first call loads the whole Keychain).
    private(set) var hasJevKey = false

    nonisolated static func name(_ source: Decision.Source) -> String {
        switch source {
        case .rules: "Rules"
        case .jev: "Jev"
        case .ollama: "Ollama"
        case .mock: "Mock"
        }
    }

    /// The questions every command asks in one pass (speculative fan-out).
    static func request(for utterance: String, frontApp: String = "") -> SystemOneRequest {
        SystemOneRequest(model: "jev-latest", state: ["utterance": utterance, "front_app": frontApp],
                         questions: [
                            "intent": .choice("What does the person want Zeus to do?", [
                                "app.open": "Open an app", "app.quit": "Quit an app", "media.play": "Play, pause or skip music",
                                "system.volume": "Change the volume", "timer.start": "Start a timer", "todo.add": "Add a to-do",
                                "calendar.query": "Ask about the calendar", "browser.open": "Open a website",
                                "chat.answer": "Answer a question", "clarify": "Unclear, needs a question back"]),
                            "risk": .score("How risky is acting on this right away?", ["read only", "reversible", "external effect", "destructive or money"]),
                         ])
    }

    private func router() -> DecisionRouter {
        // Local rules first: the fast path's own parser (no model, no network).
        let rules: @Sendable (SystemOneRequest) -> Decision? = { request in
            FastIntent.parse(request.state["utterance"] ?? "").map(\.decision)
        }
        var router = DecisionRouter(rules: rules, jev: jev, ollama: testMode ? nil : OllamaDecision())
        router.constrained = testMode || PowerState.current.constrained
        return router
    }

    /// Runs the chain (rules → Jev within the cap → Ollama) on one command. The fast path
    /// passes `announce: false` and shows the badge itself once it knows what it will do.
    @discardableResult
    func decide(_ utterance: String, forceJev: Bool = false, announce: Bool = true) async -> Record {
        var record = Record(utterance: utterance, at: Date())
        record.decision = await router().decide(Self.request(for: utterance), forceJev: forceJev)
        if record.decision != nil { remember(record) }
        if announce { onDecided?(record.engineName, record.intent) }
        await refreshBudget()
        return record
    }

    /// Keeps a decision made elsewhere (a rules hit).
    func remember(_ utterance: String, decision: Decision) {
        var record = Record(utterance: utterance, at: Date())
        record.decision = decision
        remember(record)
    }

    private func remember(_ record: Record) {
        if let d = record.decision, d.source != .jev { localCount += 1 }
        history.insert(record, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
    }

    /// The notch badge for an understood command ("Rules", "Jev") with a readable summary.
    func announce(engine: String, summary: String) { onDecided?(engine, summary) }

    /// The "Try with Jev" re-run on any earlier command.
    func tryWithJev(_ record: Record) async { await decide(record.utterance, forceJev: true) }

    func refreshBudget() async {
        let status = await jev.reservationStatus
        jevReservationStatus = status
        switch status {
        case .clear:
            budgetSummary = await jev.budget.summary
        case .inFlight:
            budgetSummary = "Jev request in flight; the local estimate may differ from billing."
        case .reconciliationRequired:
            budgetSummary = "Jev paused. Check provider usage and reconcile the pending request before retrying."
        }
    }

    /// Clears a persisted ambiguous request only after Settings tells the user to check provider usage.
    /// False when it failed: `jevMessage` says so and the caller keeps what the user typed.
    @discardableResult
    func reconcileJevPending(_ resolution: JevBudgetStore.ReservationResolution) async -> Bool {
        var succeeded = true
        do {
            try await jev.reconcilePending(resolution)
            jevMessage = nil
        } catch {
            succeeded = false
            jevMessage = "Couldn't update the pending request. Check the number and try again."
        }
        await refreshBudget()
        return succeeded
    }

    /// Whether Jev will answer instant commands: needs a key and a monthly limit.
    var jevReadiness: JevReadiness { JevReadiness.evaluate(hasKey: hasJevKey, monthlyCap: jevBudget.monthlyCap) }

    /// Jev is offered for a re-run only with a key, a cap that is not used up, and no pending request.
    var jevAvailable: Bool {
        guard hasJevKey, jevReservationStatus == .clear else { return false }
        let budget = jevBudget
        guard let cap = budget.monthlyCap, cap > 0 else { return false }
        return budget.spent < min(cap, JevBudgetStore.maxCap)
    }

    /// The Jev key goes to the Keychain once; the guard is rebuilt so the next call uses it.
    /// False when the Keychain refused: `jevMessage` says so and the caller keeps the draft.
    @discardableResult
    func saveJevKey(_ key: String) -> Bool {
        guard !testMode else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard Keychain.remove(JevKey.account) else {
                jevMessage = "Couldn't remove the key. Check Keychain access and try again."
                return false
            }
        } else {
            guard Keychain.set(trimmed, for: JevKey.account) else {
                jevMessage = "Couldn't save the key to your Keychain. It is still in the field."
                return false
            }
        }
        jevMessage = nil
        let saved = JevKey.load(from: Keychain.store)
        jev = JevGuard(key: saved, store: budgetStore)
        hasJevKey = saved != nil
        Task { await refreshBudget() }
        return true
    }

    /// The monthly cap, never above US$10 (`JevBudgetStore.maxCap`). nil switches paid calls off.
    func setJevCap(_ cap: Double?) {
        Task {
            await jev.setCap(cap)
            await refreshBudget()
        }
    }

    /// Month to date, for the meter in Settings.
    var jevBudget: JevBudget { budgetStore.load() }
}
