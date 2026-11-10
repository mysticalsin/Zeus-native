import Foundation

/// One answer set plus where it came from and what it cost.
public struct Decision: Equatable, Sendable {
    public enum Source: String, Sendable { case rules, laya, jev, ollama, mock }
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

/// Any server with the System One shape: paid Jev (api.typesafe.ai) or local Laya (laya-serve) on 127.0.0.1.
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
    public static func layaEndpoint(port: Int = 8765) -> URL { URL(string: "http://127.0.0.1:\(port)/v1/systemone")! }

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

/// Which engine answers, from Settings > Intelligence.
public enum IntelligenceEngine: String, CaseIterable, Codable, Sendable {
    case laya, jev, auto
    public var title: String {
        switch self {
        case .laya: "Laya (free, on this Mac)"
        case .jev: "Jev (cloud)"
        case .auto: "Auto (Laya, then Jev when unsure)"
        }
    }
    public static let settingsKey = "intelligence.engine"
}

/// The order Tony set: local rules, then Laya on this Mac, then paid Jev (only when Laya is unsure,
/// below 0.80, or the context is heavy, within the local estimate cap), then Ollama last, only when
/// Laya is down. Provider billing remains authoritative. `engine` narrows that chain; `constrained`
/// (Low Power Mode or a hot Mac)
/// skips the local model loads and Ollama so the Mac stays cool.
public struct DecisionRouter: Sendable {
    public var rules: (@Sendable (SystemOneRequest) -> Decision?)?
    public var laya: DecisionProvider?
    public var jev: DecisionProvider?
    public var ollama: DecisionProvider?
    public var engine: IntelligenceEngine = .laya
    public var constrained = false
    public var confidenceFloor = 0.80
    /// Estimated input tokens above which a request counts as heavy context.
    public var heavyTokens = 1_500

    public init(rules: (@Sendable (SystemOneRequest) -> Decision?)? = nil, laya: DecisionProvider? = nil,
                jev: DecisionProvider? = nil, ollama: DecisionProvider? = nil, engine: IntelligenceEngine = .auto) {
        self.rules = rules; self.laya = laya; self.jev = jev; self.ollama = ollama; self.engine = engine
    }

    /// `forceJev` is the "Try with Jev" re-run: skip rules and Laya, still inside the local estimate cap.
    public func decide(_ request: SystemOneRequest, forceJev: Bool = false) async -> Decision? {
        if forceJev { return try? await jev?.decide(request) }
        if let hit = rules?(request) { return hit }
        if engine == .jev, let paid = try? await jev?.decide(request) { return paid }
        let heavy = request.estimatedInputTokens > heavyTokens
        var local: Decision?
        var layaDown = constrained
        if !constrained, let laya {
            do { local = try await laya.decide(request) } catch { layaDown = true }
        } else { layaDown = true }
        if let local, engine == .laya { return local }
        if let local, local.confidence >= confidenceFloor, !heavy { return local }
        if engine != .laya, let paid = try? await jev?.decide(request) { return paid }
        if let local { return local }
        if layaDown, !constrained, let ollama, let fallback = try? await ollama.decide(request) { return fallback }
        return nil
    }
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
