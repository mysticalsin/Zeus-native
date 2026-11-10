import Foundation
import Testing
@testable import ZeusCore

@Suite("AI connections")
struct AIProvidersTests {
    @Test func detectionFindsCliAndApp() {
        let found = AIProviderDetector.detect(.cursor, searchDirectories: ["/a", "/b"], appDirectories: ["/Apps"],
                                              isExecutable: { $0 == "/b/cursor-agent" }, exists: { $0 == "/Apps/Cursor.app" })
        #expect(found.cliPath == "/b/cursor-agent")
        #expect(found.appPath == "/Apps/Cursor.app")
        #expect(found.isInstalled)
    }

    @Test func missingProviderIsNotInstalled() {
        let found = AIProviderDetector.detect(.ollama, searchDirectories: ["/a"], appDirectories: ["/Apps"], isExecutable: { _ in false }, exists: { _ in false })
        #expect(!found.isInstalled)
    }

    @Test func everyProviderHasATitleAndOfferKey() {
        #expect(AIProvider.allCases.count == 9)
        #expect(Set(AIProvider.allCases.map(\.offerKey)).count == 9)
        #expect(AIProvider.allCases.allSatisfy { !$0.title.isEmpty && !$0.blurb.isEmpty })
    }

    @Test func hookedProvidersMatchTheInstaller() {
        #expect(AIProvider.codex.hookAgent == .codex)
        #expect(AIProvider.gemini.hookAgent == .gemini)
        #expect(AIProvider.cursor.hookAgent == .cursor)
        #expect(AIProvider.grok.hookAgent == nil)
    }

    @Test func anyLLMURLsAreNormalised() {
        #expect(AnyLLMConfig(baseURL: "https://api.example.com/v1/", model: "m").chatURL?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(AnyLLMConfig(baseURL: "api.example.com/v1/chat/completions", model: "m").chatURL?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(AnyLLMConfig(baseURL: "http://127.0.0.1:1234/v1", model: "m").modelsURL?.absoluteString == "http://127.0.0.1:1234/v1/models")
        #expect(AnyLLMConfig(baseURL: "  ", model: "m").chatURL == nil)
        #expect(AnyLLMConfig(baseURL: "ftp://x/v1", model: "m").chatURL == nil)
    }

    @Test func anyLLMRequestCarriesKeyAndModel() throws {
        let config = AnyLLMConfig(baseURL: "https://api.example.com/v1", model: " gpt-x ")
        let request = try #require(config.request(prompt: "hi", key: "sk-1"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "gpt-x")
        #expect((body["messages"] as? [[String: String]])?.last?["content"] == "hi")
        #expect(AnyLLMConfig(baseURL: "", model: "m").request(prompt: "hi", key: nil) == nil)
    }

    @Test func plainHttpIsOnlyFineOnThisMac() {
        #expect(!AnyLLMConfig(baseURL: "http://localhost:11434/v1", model: "m").isInsecureRemote)
        #expect(AnyLLMConfig(baseURL: "http://10.0.0.5/v1", model: "m").isInsecureRemote)
        #expect(!AnyLLMConfig(baseURL: "https://api.example.com/v1", model: "m").isInsecureRemote)
    }

    @Test func streamingRequestAsksForTokensAsTheyArrive() throws {
        let config = AnyLLMConfig(baseURL: "http://127.0.0.1:11434/v1", model: "llama3.2")
        let request = try #require(config.streamingRequest(prompt: "hi", key: nil, system: "Be brief.", keepAlive: "30m"))
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["stream"] as? Bool == true)
        #expect(body["model"] as? String == "llama3.2")
        #expect(body["keep_alive"] as? String == "30m")
        #expect(AnyLLMConfig(baseURL: "http://127.0.0.1:11434/v1", model: "claude-opus-4-5").streamingRequest(prompt: "hi", key: nil) == nil)
    }

    @Test func sseParserReadsDeltasDoneAndErrors() {
        let chunk = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" there"}}]}

        data: [DONE]

        """
        #expect(OpenAICompat.parse(chunk: chunk) == [.delta("Hello"), .delta(" there"), .done])
        let error = #"{"error":{"message":"nope"}}"#
        #expect(OpenAICompat.parse(chunk: error) == [.failure("nope")])
    }

    @Test func answerIsReadFromAChatCompletion() {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":" Hello \n"}}]}"#.utf8)
        #expect(AnyLLMConfig.answer(from: data) == "Hello")
        #expect(AnyLLMConfig.answer(from: Data("{}".utf8)) == nil)
    }
}

@Suite("Jev local estimate cap")
struct JevHardCapTests {
    @Test func noSettingRaisesTheCapPastTenDollars() async {
        let suite = "zeus.test.jevcap.\(UUID().uuidString)"
        let guardian = JevGuard(key: "k", store: JevBudgetStore(suite: suite))
        await guardian.setCap(500)
        #expect(await guardian.budget.monthlyCap == 10)
        await guardian.setCap(-3)
        #expect(await guardian.budget.monthlyCap == 0)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func spendStopsAtTenEvenIfAnOldCapSaidMore() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        var budget = JevBudget(monthlyCap: 100, now: fixedDate)
        budget.record(inputTokens: 240_000_000, now: fixedDate)   // about 10.08 dollars
        let allowed = budget.allows(estimatedTokens: 1, now: fixedDate)
        #expect(!allowed)
    }
}

@Suite("Jev in-flight reservations")
struct JevReservationTests {
    @Test func reservesConcurrentSpendAndReconcilesActualUsage() async throws {
        let suite = "zeus.test.jev-reservations.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = JevBudgetStore(suite: suite)
        let request = jevRequest()
        let estimate = request.estimatedInputTokens
        let affordableTokens = Int((JevBudgetStore.maxCap / JevBudget.dollarsPerMillionInput * 1_000_000).rounded(.down))
        var initial = JevBudget(monthlyCap: JevBudgetStore.maxCap)
        initial.record(inputTokens: affordableTokens - estimate)
        let allowsWithoutReservation = initial.allows(estimatedTokens: estimate)
        let allowsWithReservation = initial.allows(estimatedTokens: estimate, reservedTokens: estimate)
        #expect(allowsWithoutReservation)
        #expect(!allowsWithReservation)
        store.save(initial)

        let transport = GatedJevTransport(response: try jevResponse(inputTokens: 1), failFirst: false)
        let client = jevClient(transport)
        let guardrail = JevGuard(key: nil, store: store, client: client)
        let first = Task { try await guardrail.decide(request) }
        await transport.waitForFirstCall()

        var secondError: Error?
        do { _ = try await guardrail.decide(request) } catch { secondError = error }
        #expect(secondError as? DecisionError == .requestInFlight)
        #expect(await transport.requestCount() == 1)
        #expect(await guardrail.reservationStatus == .inFlight)

        // A separate guard sees the persisted reservation and fails closed too.
        let duplicateGuard = JevGuard(key: nil, store: store, client: jevClient(transport))
        var duplicateError: Error?
        do { _ = try await duplicateGuard.decide(request) } catch { duplicateError = error }
        #expect(duplicateError as? DecisionError == .requestInFlight)
        #expect(await transport.requestCount() == 1)

        await transport.releaseFirstCall()
        let decision = try await first.value
        #expect(decision.inputTokens == 1)
        let settled = await guardrail.budget
        #expect(settled.inputTokens == affordableTokens - estimate + 1)
        #expect(settled.spent <= JevBudgetStore.maxCap)
        #expect(await guardrail.reservationStatus == .clear)
    }

    @Test func ambiguousProviderFailureBlocksRetryUntilUsageIsReconciled() async throws {
        let suite = "zeus.test.jev-reservation-error.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = JevBudgetStore(suite: suite)
        let request = jevRequest()
        let transport = GatedJevTransport(response: try jevResponse(inputTokens: 1), failFirst: true)
        let guardrail = JevGuard(key: nil, store: store, client: jevClient(transport))
        let first = Task { try await guardrail.decide(request) }
        await transport.waitForFirstCall()
        await transport.releaseFirstCall()

        var firstError: Error?
        do { _ = try await first.value } catch { firstError = error }
        #expect(firstError as? DecisionError == .unavailable("jev"))
        #expect(await guardrail.reservationStatus == .reconciliationRequired)

        var retryError: Error?
        do { _ = try await guardrail.decide(request) } catch { retryError = error }
        #expect(retryError as? DecisionError == .reconciliationRequired)
        #expect(await transport.requestCount() == 1)

        let recreatedGuard = JevGuard(key: nil, store: store, client: jevClient(transport))
        var recreatedError: Error?
        do { _ = try await recreatedGuard.decide(request) } catch { recreatedError = error }
        #expect(recreatedError as? DecisionError == .reconciliationRequired)
        #expect(await transport.requestCount() == 1)

        // This models a read-only provider billing check that found one billed input token.
        try await guardrail.reconcilePending(.billed(inputTokens: 1))
        #expect(await guardrail.reservationStatus == .clear)
        let retry = try await guardrail.decide(request)
        #expect(retry.inputTokens == 1)
        #expect(await transport.requestCount() == 2)
        let settled = await guardrail.budget
        #expect(settled.calls == 2)
        #expect(settled.spent <= JevBudgetStore.maxCap)
    }

    @Test func cancellationKeepsTheReservationUntilReconciliation() async throws {
        let suite = "zeus.test.jev-reservation-cancel.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = JevBudgetStore(suite: suite)
        let request = jevRequest()
        let transport = GatedJevTransport(response: try jevResponse(inputTokens: 1), failFirst: false)
        let guardrail = JevGuard(key: nil, store: store, client: jevClient(transport))
        let first = Task { try await guardrail.decide(request) }
        await transport.waitForFirstCall()
        first.cancel()
        await transport.releaseFirstCall()

        var firstError: Error?
        do { _ = try await first.value } catch { firstError = error }
        #expect(firstError as? DecisionError == .unavailable("jev"))
        #expect(await guardrail.reservationStatus == .reconciliationRequired)
        #expect(await transport.requestCount() == 1)
    }

    @Test func settingCapFromAStaleGuardPreservesSettledUsage() async throws {
        let suite = "zeus.test.jev-stale-cap.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = JevBudgetStore(suite: suite)
        let request = jevRequest()
        let transport = GatedJevTransport(response: try jevResponse(inputTokens: 1), failFirst: false)
        let activeGuard = JevGuard(key: nil, store: store, client: jevClient(transport))
        let staleGuard = JevGuard(key: nil, store: store, client: jevClient(transport))
        let call = Task { try await activeGuard.decide(request) }
        await transport.waitForFirstCall()
        await transport.releaseFirstCall()
        _ = try await call.value

        await staleGuard.setCap(5)
        let persisted = store.load()
        #expect(persisted.monthlyCap == 5)
        #expect(persisted.calls == 1)
        #expect(persisted.inputTokens == 1)
        #expect(persisted.spent == JevBudget.cost(inputTokens: 1))
    }

    @Test func usageAboveEstimateCanStillExceedTheLocalCap() async throws {
        let suite = "zeus.test.jev-reservation-overage.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = JevBudgetStore(suite: suite)
        let request = jevRequest()
        let estimate = request.estimatedInputTokens
        let affordableTokens = Int((JevBudgetStore.maxCap / JevBudget.dollarsPerMillionInput * 1_000_000).rounded(.down))
        var initial = JevBudget(monthlyCap: JevBudgetStore.maxCap)
        initial.record(inputTokens: affordableTokens - estimate)
        store.save(initial)

        let transport = GatedJevTransport(response: try jevResponse(inputTokens: estimate * 2), failFirst: false)
        let guardrail = JevGuard(key: nil, store: store, client: jevClient(transport))
        let call = Task { try await guardrail.decide(request) }
        await transport.waitForFirstCall()
        await transport.releaseFirstCall()
        let result = try await call.value
        #expect(result.inputTokens == estimate * 2)
        #expect(await guardrail.budget.spent > JevBudgetStore.maxCap)

        // Actual usage reconciles the local ledger and prevents later calls; it cannot undo
        // the overage already incurred by this call, so the local estimate is not a hard cap.
        var nextError: Error?
        do { _ = try await guardrail.decide(request) } catch { nextError = error }
        #expect(nextError as? DecisionError == .capReached)
        #expect(await transport.requestCount() == 1)
    }

    private func jevRequest() -> SystemOneRequest {
        SystemOneRequest(model: "jev-latest", state: ["task": "safe"],
                         questions: ["intent": .choice("Choose an action", ["open": "Open an app"])])
    }

    private func jevResponse(inputTokens: Int) throws -> Data {
        let response = SystemOneResponse(model: "jev-latest", answers: [:],
                                         usage: .init(input_tokens: inputTokens, output_tokens: 0))
        return try JSONEncoder().encode(response)
    }

    private func jevClient(_ transport: GatedJevTransport) -> SystemOneClient {
        SystemOneClient(source: .jev, endpoint: URL(string: "https://unit.test/v1/systemone")!, key: nil, timeout: 1) { request in
            try await transport.handle(request)
        }
    }
}

@Suite("Jev settings test-mode isolation")
struct JevSettingsTestModeTests {
    @Test func launchFlagIsExplicitAndDebugOnly() {
        let normal = ZeusStartupMode.resolve(arguments: ["Zeus"], isDebugBuild: true)
        let test = ZeusStartupMode.resolve(arguments: ["Zeus", "--jev-settings-test"], isDebugBuild: true)
        let releaseTest = ZeusStartupMode.resolve(arguments: ["Zeus", "--jev-settings-test"], isDebugBuild: false)
        let misspelled = ZeusStartupMode.resolve(arguments: ["Zeus", "--jev-settings-testing"], isDebugBuild: true)
        #expect(normal == .normal)
        #expect(normal.allowsFullAppStartup)
        #expect(test == .jevSettingsTest)
        #expect(!test.allowsFullAppStartup)
        #expect(releaseTest == .unsupportedJevSettingsTest)
        #expect(!releaseTest.allowsFullAppStartup)
        #expect(misspelled == .normal)
        #expect(misspelled.allowsFullAppStartup)
    }

    #if DEBUG
    @Test func volatileFixtureCanReconcileWithoutTouchingAnyPreferencesOrProvider() async throws {
        let suiteName = "zeus.test.jev-harness-isolation.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let sentinel = Data("pre-existing suite value".utf8)
        preferences.set(sentinel, forKey: JevBudgetStore.key)

        let preferencesBackedStore = JevBudgetStore(suite: suiteName)
        #expect(!preferencesBackedStore.seedReconciliationFixtureForTesting())
        #expect(preferences.data(forKey: JevBudgetStore.key) == sentinel)

        let store = JevBudgetStore.inMemoryForTesting()
        #expect(store.isVolatileForTesting)
        #expect(store.seedReconciliationFixtureForTesting())
        let guardian = JevGuard(key: nil, store: store)
        #expect(await guardian.reservationStatus == .reconciliationRequired)
        #expect(preferences.data(forKey: JevBudgetStore.key) == sentinel)

        let request = SystemOneRequest(model: "jev-latest", state: ["task": "synthetic UI check"],
                                       questions: ["intent": .choice("Choose an action", ["open": "Open an app"])])
        var requestError: Error?
        do { _ = try await guardian.decide(request) } catch { requestError = error }
        #expect(requestError as? DecisionError == .noKey)
        #expect(await guardian.reservationStatus == .reconciliationRequired)

        try await guardian.reconcilePending(.billed(inputTokens: 250))
        #expect(await guardian.reservationStatus == .clear)
        #expect(store.load().inputTokens == 250)
        #expect(preferences.data(forKey: JevBudgetStore.key) == sentinel)
    }
    #endif
}

private actor GatedJevTransport {
    private let response: Data
    private let failFirst: Bool
    private var requests = 0
    private var firstCallStarted = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Error>?

    init(response: Data, failFirst: Bool) {
        self.response = response
        self.failFirst = failFirst
    }

    func handle(_ _: URLRequest) async throws -> (Data, URLResponse) {
        requests += 1
        if requests == 1 {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                releaseContinuation = continuation
                firstCallStarted = true
                startedContinuation?.resume()
                startedContinuation = nil
            }
            if Task.isCancelled { throw CancellationError() }
            if failFirst { throw URLError(.timedOut) }
        }
        let url = URL(string: "https://unit.test/v1/systemone")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (self.response, response)
    }

    func waitForFirstCall() async {
        if firstCallStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            startedContinuation = continuation
        }
    }

    func releaseFirstCall() {
        releaseContinuation?.resume(returning: ())
        releaseContinuation = nil
    }

    func requestCount() -> Int { requests }
}
