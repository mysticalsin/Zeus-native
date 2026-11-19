import Foundation

/// One answer set plus where it came from and what it cost.
public struct Decision: Equatable, Sendable {
    public enum Source: String, Sendable { case rules, jev, ollama, mock }
    public var source: Source
    public var answers: [String: SystemOneAnswer]
    public var inputTokens: Int
    public var cost: Double
    public var latencyMs: Int
    /// The lowest confidence among Choice and Score answers (Nouls count by distance from 0.5).
    public var confidence: Double {
        let values = answers.values.compactMap { a -> Double? in
            if let c = a.confidence { return c }
            if let n = a.noul { return abs(n - 0.5) * 2 }
            return nil
        }
        return values.min() ?? 0
    }
    public init(source: Source, answers: [String: SystemOneAnswer], inputTokens: Int = 0, cost: Double = 0, latencyMs: Int = 0) {
        self.source = source; self.answers = answers; self.inputTokens = inputTokens; self.cost = cost; self.latencyMs = latencyMs
    }
}

public enum DecisionError: Error, Equatable {
    case noKey, capReached, requestInFlight, reconciliationRequired, noPendingReservation, unavailable(String), http(Int), badResponse
}

public protocol DecisionProvider: Sendable {
    var source: Decision.Source { get }
    func decide(_ request: SystemOneRequest) async throws -> Decision
}

/// A server with the System One shape: paid Jev (api.typesafe.ai).
public struct SystemOneClient: DecisionProvider {
    public let source: Decision.Source
    let endpoint: URL
    let key: String?
    let timeout: TimeInterval
    let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(source: Decision.Source, endpoint: URL, key: String?, timeout: TimeInterval,
                transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        self.source = source; self.endpoint = endpoint; self.key = key; self.timeout = timeout; self.transport = transport
    }

    public static let jevEndpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    public func decide(_ body: SystemOneRequest) async throws -> Decision {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let started = Date()
        let data: Data, response: URLResponse
        do { (data, response) = try await transport(request) } catch { throw DecisionError.unavailable(source.rawValue) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw DecisionError.http(http.statusCode) }
        guard let parsed = try? JSONDecoder().decode(SystemOneResponse.self, from: data) else { throw DecisionError.badResponse }
        guard parsed.usage.input_tokens >= 0, parsed.usage.output_tokens >= 0 else { throw DecisionError.badResponse }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let cost = source == .jev ? JevBudget.cost(inputTokens: parsed.usage.input_tokens) : 0
        return Decision(source: source, answers: parsed.answers, inputTokens: parsed.usage.input_tokens, cost: cost, latencyMs: ms)
    }
}

/// Paid Jev behind a process-local estimate guard. This cannot enforce a provider-side hard dollar cap.
public actor JevGuard: DecisionProvider {
    public nonisolated let source = Decision.Source.jev
    private let client: SystemOneClient?
    private let store: JevBudgetStore
    public private(set) var budget: JevBudget
    private var activeReservationID: UUID?
    public var reservationStatus: JevBudgetStore.ReservationStatus { store.reservationStatus }

    public init(key: String?, store: JevBudgetStore = JevBudgetStore(), client: SystemOneClient? = nil) {
        self.store = store
        self.budget = store.load()
        store.markExistingReservationUncertain()
        if let client { self.client = client }
        else if let key, !key.isEmpty { self.client = SystemOneClient(source: .jev, endpoint: SystemOneClient.jevEndpoint, key: key, timeout: 3) }
        else { self.client = nil }
    }

    public func decide(_ request: SystemOneRequest) async throws -> Decision {
        guard let client else { throw DecisionError.noKey }
        guard activeReservationID == nil else { throw DecisionError.requestInFlight }
        let estimatedTokens = request.estimatedInputTokens
        let reservationID = UUID()
        switch store.reserve(id: reservationID, estimatedInputTokens: estimatedTokens) {
        case .reserved(let updated):
            budget = updated
            activeReservationID = reservationID
        case .capReached(let updated):
            budget = updated
            throw DecisionError.capReached
        case .inFlight:
            throw DecisionError.requestInFlight
        case .reconciliationRequired:
            throw DecisionError.reconciliationRequired
        }

        // One persisted reservation at a time closes the same-process actor reentrancy gap.
        // Any thrown outcome is ambiguous: timeouts, cancellation, HTTP errors, and bad responses
        // do not prove the provider did no billable work. Keep the reservation and pause retries.
        do {
            let decision = try await client.decide(request)
            guard let settled = store.settle(id: reservationID, actualInputTokens: decision.inputTokens) else {
                store.markUncertain(id: reservationID)
                activeReservationID = nil
                throw DecisionError.reconciliationRequired
            }
            budget = settled
            activeReservationID = nil
            return decision
        } catch {
            store.markUncertain(id: reservationID)
            activeReservationID = nil
            throw error
        }
    }

    /// Resolve an ambiguous pending request only after checking its provider-side usage record.
    public func reconcilePending(_ resolution: JevBudgetStore.ReservationResolution) throws {
        guard activeReservationID == nil else { throw DecisionError.requestInFlight }
        guard let updated = store.reconcilePending(resolution) else { throw DecisionError.noPendingReservation }
        budget = updated
    }

    public func setCap(_ cap: Double?) {
        guard let updated = store.updateCap(cap) else { return }
        budget = updated
    }
}

/// The one model stage of instant commands. Older builds stored a retired choice under `settingsKey`;
/// any such value now means Jev, and `migrateStoredChoice` rewrites the saved value once.
public enum IntelligenceEngine: String, CaseIterable, Codable, Sendable {
    case jev
    public var title: String { "Jev (cloud)" }
    public static let settingsKey = "intelligence.engine"

    /// Any stored value (including a retired one) maps to Jev. Returns whether the stored value changed.
    @discardableResult
    public static func migrateStoredChoice(in defaults: UserDefaults) -> Bool {
        guard let stored = defaults.string(forKey: settingsKey), stored != IntelligenceEngine.jev.rawValue else { return false }
        defaults.set(IntelligenceEngine.jev.rawValue, forKey: settingsKey)
        return true
    }
}

/// Why Jev will or will not answer an instant command right now (for Settings).
public enum JevReadiness: Equatable, Sendable {
    case noKey, noMonthlyLimit, ready
    public static func evaluate(hasKey: Bool, monthlyCap: Double?) -> JevReadiness {
        guard hasKey else { return .noKey }
        guard let cap = monthlyCap, cap > 0 else { return .noMonthlyLimit }
        return .ready
    }
    public var statusText: String {
        switch self {
        case .noKey: "No key saved. Commands go to the assistant."
        case .noMonthlyLimit: "Set a monthly limit to turn Jev on"
        case .ready: "Jev is on"
        }
    }
}

/// Local rules, then paid Jev (needs a key and a monthly cap; `JevGuard` refuses otherwise), then Ollama
/// only if it is already answering on this Mac (never launched). Everything after the rules shares one
/// time budget; when it runs out the caller gets nil and the LLM brain takes the request. The late call
/// is never cancelled: a cancelled Jev request would leave its billing reservation uncertain.
/// `constrained` (Low Power Mode or a hot Mac) skips Ollama so the Mac stays cool.
public struct DecisionRouter: Sendable {
    public var rules: (@Sendable (SystemOneRequest) -> Decision?)?
    public var jev: DecisionProvider?
    public var ollama: DecisionProvider?
    public var constrained = false
    /// Longest an instant command may delay the voice turn.
    public var budget: Duration = .milliseconds(600)

    public init(rules: (@Sendable (SystemOneRequest) -> Decision?)? = nil, jev: DecisionProvider? = nil,
                ollama: DecisionProvider? = nil, budget: Duration = .milliseconds(600)) {
        self.rules = rules; self.jev = jev; self.ollama = ollama; self.budget = budget
    }

    /// `forceJev` is the "Try with Jev" re-run: skip rules, still inside the local estimate cap.
    public func decide(_ request: SystemOneRequest, forceJev: Bool = false) async -> Decision? {
        if forceJev { return try? await jev?.decide(request) }
        if let hit = rules?(request) { return hit }
        let jev = jev, ollama = constrained ? nil : ollama
        let task = Task<Decision?, Never> {
            if let paid = try? await jev?.decide(request) { return paid }
            if let ollama, let fallback = try? await ollama.decide(request) { return fallback }
            return nil
        }
        return await DecisionRace.first(task, within: budget)
    }
}

/// Lets exactly one of the task result and the timer through; the task keeps running after a timeout.
enum DecisionRace {
    static func first<T: Sendable>(_ task: Task<T?, Never>, within limit: Duration) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = DecisionOnce()
            Task { let value = await task.value; if gate.open() { continuation.resume(returning: value) } }
            Task { try? await Task.sleep(for: limit); if gate.open() { continuation.resume(returning: nil) } }
        }
    }
}

private final class DecisionOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func open() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}

public enum JevKey {
    public static let account = "jev-api-key"
    /// The consolidated Keychain item first, then the JEV_API_KEY environment variable.
    public static func load(from store: KeychainStore, env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let key = store.get(account), !key.isEmpty { return key }
        if let key = env["JEV_API_KEY"], !key.isEmpty { return key }
        return nil
    }
}
