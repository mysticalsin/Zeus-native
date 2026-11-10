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

    @Test func routerPrefersConfidentLayaAndEscalatesUnsure() async {
        let sure = DecisionRouter(laya: Fixed(source: .laya, confidence: 0.9, fails: false), jev: Fixed(source: .jev, confidence: 0.99, fails: false))
        #expect(await sure.decide(sample())?.source == .laya)
        let unsure = DecisionRouter(laya: Fixed(source: .laya, confidence: 0.5, fails: false), jev: Fixed(source: .jev, confidence: 0.99, fails: false))
        #expect(await unsure.decide(sample())?.source == .jev)
        let capped = DecisionRouter(laya: Fixed(source: .laya, confidence: 0.5, fails: false), jev: Fixed(source: .jev, confidence: 0.99, fails: true),
                                    ollama: Fixed(source: .ollama, confidence: 0.6, fails: false))
        #expect(await capped.decide(sample())?.source == .laya)
        let layaDown = DecisionRouter(laya: Fixed(source: .laya, confidence: nil, fails: true), jev: Fixed(source: .jev, confidence: 0.9, fails: true),
                                     ollama: Fixed(source: .ollama, confidence: 0.6, fails: false))
        #expect(await layaDown.decide(sample())?.source == .ollama)
    }

    @Test func engineChoiceAndTryWithJev() async {
        var router = DecisionRouter(laya: Fixed(source: .laya, confidence: 0.4, fails: false), jev: Fixed(source: .jev, confidence: 0.9, fails: false), engine: .laya)
        #expect(await router.decide(sample())?.source == .laya)
        #expect(await router.decide(sample(), forceJev: true)?.source == .jev)
        router.engine = .jev
        #expect(await router.decide(sample())?.source == .jev)
        router.engine = .auto
        router.constrained = true
        router.ollama = Fixed(source: .ollama, confidence: 0.6, fails: false)
        #expect(await router.decide(sample())?.source == .jev)
    }

    @Test func rulesWinFirst() async {
        let router = DecisionRouter(rules: { _ in Decision(source: .rules, answers: [:]) }, laya: Fixed(source: .laya, confidence: 0.9, fails: false))
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
