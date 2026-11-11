import Foundation
import Testing
@testable import ZeusCore

private struct Fixed: DecisionProvider {
    let source: Decision.Source
    let confidence: Double?
    let fails: Bool
    func decide(_ request: SystemOneRequest) async throws -> Decision {
        if fails { throw DecisionError.unavailable(source.rawValue) }
        return Decision(source: source, answers: ["intent": SystemOneAnswer(type: "choice", choice: "app.open", confidence: confidence)])
    }
}

private func sample(_ utterance: String = "open safari") -> SystemOneRequest {
    SystemOneRequest(model: "jev-latest", state: ["utterance": utterance],
                     questions: ["intent": .choice("What does the user want?", ["app.open": "Open an app", "chat.answer": "Answer a question"])])
}

/// A latch the test opens by hand, so a "slow" provider is slow without any wall-clock sleep.
private actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

private func day(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }

@Suite struct DecisionTests {
    @Test func requestEncodesSystemOneShape() throws {
        let json = String(decoding: try JSONEncoder().encode(sample()), as: UTF8.self)
        #expect(json.contains("\"criteria\":{"))
        #expect(json.contains("\"model\":\"jev-latest\""))
    }

    @Test func budgetCapsAtTenDollarsAndRollsMonthly() {
        var b = JevBudget(monthlyCap: 10, now: day("2026-10-15"))
        #expect(JevBudget.cost(inputTokens: 1_000_000) == 0.042)
        let ok = b.allows(estimatedTokens: 1000, now: day("2026-10-15"))
        #expect(ok)
        b.record(inputTokens: 238_000_000, now: day("2026-10-20"))
        #expect(b.spent > 9.99)
        let blocked = b.allows(estimatedTokens: 1_000_000, now: day("2026-10-31"))
        #expect(!blocked)
        let next = b.allows(estimatedTokens: 1000, now: day("2026-11-01"))
        #expect(next)
        #expect(b.spent == 0)
        #expect(b.summary == "Jev $0.00 of $10")
    }

    @Test func noCapMeansNoPaidCalls() {
        var b = JevBudget(monthlyCap: nil)
        let allowed = b.allows(estimatedTokens: 1)
        #expect(!allowed)
    }

    private static let jevBody = #"{"model":"jev-1","answers":{"intent":{"type":"choice","choice":"app.open","confidence":0.97}},"usage":{"input_tokens":100,"output_tokens":5}}"#

    private func jevGuard(key: String?, cap: Double?, hold: Latch? = nil) -> (JevGuard, JevBudgetStore) {
        let store = JevBudgetStore.inMemoryForTesting()
        _ = store.updateCap(cap)
        let client = SystemOneClient(source: .jev, endpoint: SystemOneClient.jevEndpoint, key: key ?? "k", timeout: 3) { request in
            await hold?.wait()
            return (Data(Self.jevBody.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return (JevGuard(key: key, store: store, client: key == nil ? nil : client), store)
    }

    @Test func chainWithoutKeyGoesToTheLLM() async {
        let (jev, _) = jevGuard(key: nil, cap: 5)
        #expect(await DecisionRouter(jev: jev).decide(sample()) == nil)
    }

    @Test func chainWithKeyButNoCapGoesToTheLLMAndSaysWhy() async {
        let (jev, _) = jevGuard(key: "k", cap: nil)
        #expect(await DecisionRouter(jev: jev).decide(sample()) == nil)
        #expect(JevReadiness.evaluate(hasKey: true, monthlyCap: nil) == .noMonthlyLimit)
        #expect(JevReadiness.noMonthlyLimit.statusText == "Set a monthly limit to turn Jev on")
        #expect(JevReadiness.evaluate(hasKey: false, monthlyCap: 5) == .noKey)
        #expect(JevReadiness.evaluate(hasKey: true, monthlyCap: 5) == .ready)
    }

    @Test func chainWithKeyAndCapUsesJev() async {
        let (jev, _) = jevGuard(key: "k", cap: 5)
        #expect(await DecisionRouter(jev: jev).decide(sample())?.source == .jev)
    }

    /// The provider is held shut until the router has already answered, so a nil result can only come
    /// from the 200 ms deadline firing, never from the provider finishing. No wall-clock bound is
    /// asserted: the whole target runs in one process with thousands of parallel tests, and the
    /// cooperative pool can delay any timer by seconds there (a 1.5 s bound failed at 6.2 s on CI while
    /// the deadline logic was correct).
    @Test(.timeLimit(.minutes(1))) func jevTimeoutFallsToTheLLMWithinTheBudget() async {
        let latch = Latch()
        let (jev, store) = jevGuard(key: "k", cap: 5, hold: latch)
        let router = DecisionRouter(jev: jev, budget: .milliseconds(200))
        let decision = await router.decide(sample())
        #expect(decision == nil)
        // The late call is not cancelled: it still settles once released.
        await latch.open()
        for _ in 0..<500 where store.reservationStatus != .clear { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(store.reservationStatus == .clear)
        #expect(store.load().calls == 1)
    }

    @Test func ollamaOnlyAnswersWhenJevGaveNothingAndNeverWhenConstrained() async {
        var router = DecisionRouter(jev: Fixed(source: .jev, confidence: nil, fails: true), ollama: Fixed(source: .ollama, confidence: 0.6, fails: false))
        #expect(await router.decide(sample())?.source == .ollama)
        router.constrained = true
        #expect(await router.decide(sample()) == nil)
        router.jev = Fixed(source: .jev, confidence: 0.9, fails: false)
        #expect(await router.decide(sample())?.source == .jev)
    }

    @Test func tryWithJevSkipsRules() async {
        let router = DecisionRouter(rules: { _ in Decision(source: .rules, answers: [:]) }, jev: Fixed(source: .jev, confidence: 0.9, fails: false))
        #expect(await router.decide(sample(), forceJev: true)?.source == .jev)
    }

    @Test func storedLayaOrAutoPreferenceMigratesToJev() {
        for old in ["laya", "auto", "garbage"] {
            let defaults = UserDefaults(suiteName: "zeus.test.engine.\(UUID().uuidString)")!
            defaults.set(old, forKey: IntelligenceEngine.settingsKey)
            #expect(IntelligenceEngine.migrateStoredChoice(in: defaults))
            #expect(defaults.string(forKey: IntelligenceEngine.settingsKey) == "jev")
            #expect(!IntelligenceEngine.migrateStoredChoice(in: defaults))
        }
        let fresh = UserDefaults(suiteName: "zeus.test.engine.\(UUID().uuidString)")!
        #expect(!IntelligenceEngine.migrateStoredChoice(in: fresh))
        #expect(fresh.object(forKey: IntelligenceEngine.settingsKey) == nil)
    }

    @Test func rulesWinFirst() async {
        let router = DecisionRouter(rules: { _ in Decision(source: .rules, answers: [:]) }, jev: Fixed(source: .jev, confidence: 0.9, fails: false))
        #expect(await router.decide(sample())?.source == .rules)
    }

    @Test func jevGuardRefusesWithoutKeyAndCountsSpend() async throws {
        let suite = "zeus.test.jev.\(UUID().uuidString)"
        let store = JevBudgetStore(suite: suite)
        let none = JevGuard(key: nil, store: store)
        await #expect(throws: DecisionError.noKey) { try await none.decide(sample()) }
        let body = #"{"model":"jev-1","answers":{"intent":{"type":"choice","choice":"app.open","confidence":0.97,"probabilities":{"app.open":0.97,"chat.answer":0.03}}},"usage":{"input_tokens":2000000,"output_tokens":5}}"#
        let client = SystemOneClient(source: .jev, endpoint: SystemOneClient.jevEndpoint, key: "test", timeout: 1) { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test")
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let paid = JevGuard(key: "test", store: store, client: client)
        let decision = try await paid.decide(sample())
        #expect(decision.answers["intent"]?.choice == "app.open")
        #expect(abs(decision.cost - 0.084) < 1e-9)
        #expect(abs(store.load().spent - 0.084) < 1e-9)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func keyComesFromKeychainThenEnv() {
        let empty = KeychainStore(backend: MemoryKeychain(), defaults: UserDefaults(suiteName: "zeus.test.jk.\(UUID().uuidString)")!)
        #expect(JevKey.load(from: empty, env: [:]) == nil)
        #expect(JevKey.load(from: empty, env: ["JEV_API_KEY": "e"]) == "e")
        let stored = KeychainStore(backend: MemoryKeychain(["com.zeus.app|jev-api-key": "k"]), defaults: UserDefaults(suiteName: "zeus.test.jk.\(UUID().uuidString)")!)
        #expect(JevKey.load(from: stored, env: ["JEV_API_KEY": "e"]) == "k")
    }
}
