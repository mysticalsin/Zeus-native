import Foundation
import Observation
import ZeusCore

/// The decision engine for commands: local rules, then Laya on this Mac, then Jev in the cloud
/// (inside the local estimate cap), then Ollama last. Provider billing remains authoritative.
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

    var engine: IntelligenceEngine {
        didSet { engineDefaults?.set(engine.rawValue, forKey: IntelligenceEngine.settingsKey) }
    }

    private let budgetStore: JevBudgetStore
    private let engineDefaults: UserDefaults?
    private let testMode: Bool
    private let layaProvider: DecisionProvider?
    private let layaHelper: LayaHelper?
    private var jev: JevGuard

    private init() {
        let store = JevBudgetStore()
        let laya = LayaHelper.shared
        budgetStore = store
        engineDefaults = .standard
        testMode = false
        layaProvider = laya
        layaHelper = laya
        engine = IntelligenceEngine(rawValue: UserDefaults.standard.string(forKey: IntelligenceEngine.settingsKey) ?? "") ?? .laya
        jev = JevGuard(key: JevKey.load(from: Keychain.store), store: store)
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
        engineDefaults = nil
        testMode = true
        layaProvider = nil
        layaHelper = nil
        engine = .laya
        jev = JevGuard(key: nil, store: testStore)
        Task { await refreshBudget() }
    }
    #endif

    var hasJevKey: Bool { !testMode && JevKey.load(from: Keychain.store) != nil }
    var layaInstalled: Bool { layaHelper?.installed ?? false }
    var layaRunning: Bool { layaHelper?.running ?? false }

    nonisolated static func name(_ source: Decision.Source) -> String {
        switch source {
        case .rules: "Rules"
        case .laya: "Laya"
        case .jev: "Jev"
        case .ollama: "Ollama"
        case .mock: "Mock"
        }
    }

    /// The questions every command asks in one pass (speculative fan-out).
    static func request(for utterance: String, frontApp: String = "") -> SystemOneRequest {
        SystemOneRequest(model: "jev-latest", state: ["utterance": utterance, "front_app": frontApp],
                         questions: [
                            "intent": .choice("What does the person want ZEUS to do?", [
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
        var router = DecisionRouter(rules: rules, laya: layaProvider, jev: jev,
                                    ollama: testMode ? nil : OllamaDecision(), engine: engine)
        router.constrained = testMode || PowerState.current.constrained
        return router
    }

    /// Runs the chain (rules → Laya → Jev within the cap → Ollama) on one command. The fast path
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

    /// Keeps a decision made elsewhere (a rules hit, or a speculative Laya answer that was used).
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

    /// The notch badge for an understood command ("Rules", "Laya", "Jev") with a readable summary.
    func announce(engine: String, summary: String) { onDecided?(engine, summary) }

    /// Whether a partial transcript may be sent to Laya ahead of time. Only Laya (free, on this
    /// Mac) is ever asked speculatively; Jev is never called on a partial, and an explicit Jev
    /// choice in Settings means no speculation at all.
    var speculates: Bool {
        !testMode && engine != .jev && layaInstalled && !PowerState.current.constrained
    }

    /// Laya alone, for a speculative partial. Not kept in the history; nil when Laya is unavailable.
    func layaOnly(_ utterance: String) async -> Decision? {
        guard speculates, let layaProvider else { return nil }
        return try? await layaProvider.decide(Self.request(for: utterance))
    }

    /// The confidence below which Auto asks Jev (`DecisionRouter.confidenceFloor`).
    static let confidenceFloor = DecisionRouter().confidenceFloor

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
        jev = JevGuard(key: JevKey.load(from: Keychain.store), store: budgetStore)
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
