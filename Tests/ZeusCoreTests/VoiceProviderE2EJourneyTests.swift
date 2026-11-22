import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

/// Deep fake journeys for `qa/providers-e2e/run.sh`. No real keys. The verifier owns the tables below.
@Suite("Voice provider end-to-end journeys", .serialized)
struct VoiceProviderE2EJourneyTests {
    private let key = "zeus-e2e-fake-key"
    private let other = "zeus-e2e-other-key"

    @Test func firstAddValidatePickTestAndReply() async throws {
        let harness = try JourneyHarness()
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: key)
        #expect(await harness.session.readiness(for: ElevenLabsTTSAdapter.id) == .ready)
        await harness.session.chooseVoice(providerID: ElevenLabsTTSAdapter.id, voiceID: "zeus.synthetic")
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        let test = await harness.session.speak("This is Zeus.")
        guard case .cloud = test.route else { Issue.record("test voice did not use the provider"); return }
        #expect(VoiceAudioValidity.isPlayable(test.audio))
        #expect(harness.local.calls == 0)
        let reply = await harness.session.speak("A reply turn.")
        guard case .cloud(let id, _) = reply.route else { Issue.record("reply did not use the provider"); return }
        #expect(id == ElevenLabsTTSAdapter.id)
        #expect(harness.local.calls == 0)
        record(test.firstAudioMs)
        record(reply.firstAudioMs)
        assertNoSecret(harness)
    }

    @Test func editTheKeyThenRemoveIt() async throws {
        let harness = try JourneyHarness()
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: key)
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: other)
        let account = VoiceProviderAccounts.keyAccount(for: ElevenLabsTTSAdapter.id)
        #expect(harness.store.read(service: VoiceProviderAccounts.service, account: account) == other)
        await harness.session.remove(providerID: ElevenLabsTTSAdapter.id)
        #expect(harness.store.read(service: VoiceProviderAccounts.service, account: account) == nil)
        #expect(await harness.session.choice == .local)
        #expect(await harness.session.readiness(for: ElevenLabsTTSAdapter.id) == .unset)
        assertNoSecret(harness)
    }

    @Test func switchProviderMidSession() async throws {
        let harness = try JourneyHarness()
        await ready(harness, ElevenLabsTTSAdapter.id, key)
        await ready(harness, GoogleCloudTTSAdapter.id, other)
        await harness.session.select(.provider(GoogleCloudTTSAdapter.id))
        let spoken = await harness.session.speak("Switch.")
        guard case .cloud(let id, _) = spoken.route else { Issue.record("switch did not speak"); return }
        #expect(id == GoogleCloudTTSAdapter.id)
        #expect(harness.transport.hosts.contains { $0.contains("googleapis") })
        assertNoSecret(harness)
    }

    @Test func switchMidUtteranceCutsCleanly() async throws {
        let harness = try JourneyHarness()
        await ready(harness, ElevenLabsTTSAdapter.id, key)
        await ready(harness, GoogleCloudTTSAdapter.id, other)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        harness.transport.holdStreams = true
        let session = harness.session
        let task = Task { await session.speak("Hold this.") }
        for _ in 0..<50 {
            if harness.transport.inFlight > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.transport.inFlight == 1)
        await session.cancel()
        let cancelled = await task.value
        #expect(cancelled.route == .cancelled)
        harness.transport.holdStreams = false
        for _ in 0..<50 {
            if harness.transport.inFlight == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.transport.inFlight == 0)
        await session.select(.provider(GoogleCloudTTSAdapter.id))
        let next = await session.speak("Next provider.")
        guard case .cloud(let id, _) = next.route else { Issue.record("next utterance did not start"); return }
        #expect(id == GoogleCloudTTSAdapter.id)
        #expect(harness.transport.maxOverlap == 1)
        assertNoSecret(harness)
    }

    @Test func relaunchKeepsTheKeyTheVoiceAndTheChoice() async throws {
        let harness = try JourneyHarness()
        await ready(harness, ElevenLabsTTSAdapter.id, key)
        await harness.session.chooseVoice(providerID: ElevenLabsTTSAdapter.id, voiceID: "zeus.synthetic")
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        let again = VoiceProviderSession(store: harness.store, transport: harness.transport, local: harness.local,
                                         preferences: harness.preferences, log: harness.log, signposter: harness.signposter,
                                         firstAudioBudgetMs: 30_000)
        #expect(await again.choice == .provider(ElevenLabsTTSAdapter.id))
        let account = VoiceProviderAccounts.keyAccount(for: ElevenLabsTTSAdapter.id)
        #expect(harness.store.read(service: VoiceProviderAccounts.service, account: account) == key)
        #expect(harness.store.read(service: VoiceProviderAccounts.service, account: "elevenlabs.voice-id") == "zeus.synthetic")
        let before = await again.speak("Before validate.")
        #expect(before.route == .local(.notReady))
        #expect(!harness.transport.requests.contains { $0.httpBodyContains("Before validate.") })
        assertNoSecret(harness)
    }

    @Test func emptyAndMalformedKeysNeverLeaveTheMachine() async throws {
        let harness = try JourneyHarness()
        for bad in ["", "   ", "short", "has space", "bad\nkey!!"] {
            await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: bad)
            #expect(await harness.session.readiness(for: ElevenLabsTTSAdapter.id) == .unset)
        }
        #expect(harness.transport.requests.isEmpty)
        #expect(!VoiceProviderKeyPolicy.accepts(""))
        #expect(!VoiceProviderKeyPolicy.accepts("1234567"))
        #expect(VoiceProviderKeyPolicy.accepts("12345678"))
        assertNoSecret(harness)
    }

    @Test func aBadKeyIsUnauthorized() async throws {
        let harness = try JourneyHarness()
        harness.transport.validateStatus = 401
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: key)
        #expect(await harness.session.readiness(for: ElevenLabsTTSAdapter.id) == .error(.unauthorized))
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        let spoken = await harness.session.speak("No.")
        #expect(spoken.route == .local(.notReady))
        #expect(!harness.transport.requests.contains { $0.httpBodyContains("No.") })
        assertNoSecret(harness)
    }

    @Test func aRevokedKeyMidSessionFallsBackAndStaysInError() async throws {
        let harness = try JourneyHarness()
        await ready(harness, ElevenLabsTTSAdapter.id, key)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        harness.transport.speakStatus = 401
        let spoken = await harness.session.speak("Revoked.")
        #expect(spoken.route == .local(.failed(.unauthorized)))
        #expect(await harness.session.readiness(for: ElevenLabsTTSAdapter.id) == .error(.unauthorized))
        let calls = harness.transport.requests.count
        let again = await harness.session.speak("Again.")
        #expect(again.route == .local(.notReady))
        #expect(harness.transport.requests.count == calls)
        #expect(harness.local.calls >= 1)
        assertNoSecret(harness)
    }

    @Test func rateLimitAndServerErrorsFallback() async throws {
        let limited = try JourneyHarness()
        await ready(limited, ElevenLabsTTSAdapter.id, key)
        await limited.session.select(.provider(ElevenLabsTTSAdapter.id))
        limited.transport.speakStatus = 429
        let rate = await limited.session.speak("Slow down.")
        #expect(rate.route == .local(.failed(.rateLimited)))
        #expect(await limited.session.readiness(for: ElevenLabsTTSAdapter.id) == .error(.rateLimited))

        let down = try JourneyHarness()
        await ready(down, ElevenLabsTTSAdapter.id, key)
        await down.session.select(.provider(ElevenLabsTTSAdapter.id))
        down.transport.speakStatus = 503
        let server = await down.session.speak("Down.")
        #expect(server.route == .local(.failed(.server(503))))
        #expect(await down.session.readiness(for: ElevenLabsTTSAdapter.id) == .ready)
        #expect(down.local.calls == 1)
    }

    @Test func networkDownUsesLocalThenTheMacVoice() async throws {
        let harness = try JourneyHarness(localEmpty: true)
        await ready(harness, ElevenLabsTTSAdapter.id, key)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        harness.transport.offline = true
        let spoken = await harness.session.speak("Offline.")
        #expect(spoken.route == .local(.failed(.offline)))
        #expect(spoken.statusLine.contains("Mac voice"))
        #expect(harness.system.calls == 1)
        #expect(!spoken.audio.isEmpty)
        #expect(ProviderFailure.wrap(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)) == .offline)
    }

    @Test func aSlowFirstBytePastTheBudgetFallsBack() async throws {
        let harness = try JourneyHarness()
        await ready(harness, ElevenLabsTTSAdapter.id, key)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        await harness.session.setFirstAudioBudget(ms: 5)
        harness.transport.delayMs = 40
        let spoken = await harness.session.speak("Late.")
        #expect(spoken.route == .local(.timedOut))
        #expect(harness.local.calls == 1)
    }

    @Test func aTruncatedStreamAndInvalidAudioFallBack() async throws {
        let truncated = try JourneyHarness()
        await ready(truncated, ElevenLabsTTSAdapter.id, key)
        await truncated.session.select(.provider(ElevenLabsTTSAdapter.id))
        truncated.transport.truncate = true
        let cut = await truncated.session.speak("Cut.")
        #expect(cut.route == .local(.failed(.invalidResponse)))
        #expect(truncated.local.calls == 1)

        let invalid = try JourneyHarness()
        await ready(invalid, ElevenLabsTTSAdapter.id, key)
        await invalid.session.select(.provider(ElevenLabsTTSAdapter.id))
        invalid.transport.invalidAudio = true
        let junk = await invalid.session.speak("Junk.")
        #expect(junk.route == .local(.failed(.invalidResponse)))
        #expect(!VoiceAudioValidity.isPlayable(Data("NOPE".utf8)))
        #expect(VoiceAudioValidity.isPlayable(VoiceProviderFakeAudio.wavSilence()))
    }

    @Test func thirtyFastRepliesMeetTheLatencyBudgets() async throws {
        let harness = try JourneyHarness()
        await ready(harness, ElevenLabsTTSAdapter.id, key)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        var samples: [Int] = []
        for _ in 0..<30 {
            let spoken = await harness.session.speak("Latency.")
            guard case .cloud = spoken.route else { Issue.record("latency sample was not cloud"); return }
            samples.append(spoken.firstAudioMs)
            record(spoken.firstAudioMs)
        }
        let sorted = samples.sorted()
        let p50 = sorted[14]
        let p95 = sorted[28]
        #expect(p50 <= ProviderLatencyVerdict.firstAudioP50Ms)
        #expect(p95 <= ProviderLatencyVerdict.directStreamP95Ms)
        #expect(p50 <= ProviderLatencyVerdict.voiceLegMs)
        #expect(p95 <= 1_400)
    }

    @Test func everyTransitionIsListed() {
        let rows: [(ProviderReadiness, ProviderReadinessEvent, ProviderReadiness, ProviderReadinessEffect)] = [
            (.unset, .saveCredential, .validating, .beginValidation),
            (.unset, .validationStarted, .unset, .ignored),
            (.unset, .validationSucceeded, .unset, .ignored),
            (.unset, .validationFailed(.unauthorized), .unset, .ignored),
            (.unset, .runtimeFailure(.server(500)), .unset, .ignored),
            (.unset, .retry, .unset, .ignored),
            (.unset, .remove, .unset, .deleteCredential),
            (.validating, .saveCredential, .validating, .beginValidation),
            (.validating, .validationStarted, .validating, .ignored),
            (.validating, .validationSucceeded, .ready, .ignored),
            (.validating, .validationFailed(.unauthorized), .error(.unauthorized), .ignored),
            (.validating, .runtimeFailure(.timedOut), .validating, .ignored),
            (.validating, .retry, .validating, .beginValidation),
            (.validating, .remove, .unset, .deleteCredential),
            (.ready, .saveCredential, .validating, .beginValidation),
            (.ready, .validationStarted, .ready, .ignored),
            (.ready, .validationSucceeded, .ready, .ignored),
            (.ready, .validationFailed(.rateLimited), .ready, .ignored),
            (.ready, .runtimeFailure(.rateLimited), .error(.rateLimited), .ignored),
            (.ready, .retry, .ready, .ignored),
            (.ready, .remove, .unset, .deleteCredential),
            (.error(.unauthorized), .saveCredential, .validating, .beginValidation),
            (.error(.unauthorized), .validationStarted, .error(.unauthorized), .ignored),
            (.error(.unauthorized), .validationSucceeded, .error(.unauthorized), .ignored),
            (.error(.timedOut), .validationFailed(.server(500)), .error(.timedOut), .ignored),
            (.error(.offline), .runtimeFailure(.offline), .error(.offline), .ignored),
            (.error(.rateLimited), .retry, .validating, .beginValidation),
            (.error(.server(503)), .remove, .unset, .deleteCredential),
        ]
        #expect(rows.count == 28)
        for row in rows {
            var machine = ProviderReadinessMachine(state: row.0)
            let effect = machine.reduce(row.1)
            #expect(machine.state == row.2)
            #expect(effect == row.3)
        }
    }

    /// Verifier-owned: the generator and the invariants live in this test, not in the session.
    @Test func verifierOwnsThePropertyWalk() {
        var rng = E2ESplitMix(seed: 0xE2E)
        let events = ProviderReadinessEvent.allProbe
        for _ in 0..<80 {
            var machine = ProviderReadinessMachine()
            var secret = "k"
            for _ in 0..<12 { secret.append(String(rng.next() % 10)) }
            for _ in 0..<16 {
                let event = events[Int(rng.next() % UInt64(events.count))]
                let before = machine.state
                let effect = machine.reduce(event)
                if effect == .ignored, machine.state != before {
                    let legal = legalChange(before, event, machine.state)
                    #expect(legal)
                }
                #expect(!String(describing: machine.state).contains(secret))
            }
            #expect(machine.reduce(.remove) == .deleteCredential)
            #expect(machine.state == .unset)
        }
    }

    @Test func specBoundaries() {
        #expect(ProviderLatencyVerdict.meetsVoiceLeg(600))
        #expect(!ProviderLatencyVerdict.meetsVoiceLeg(601))
        #expect(ProviderLatencyVerdict.meetsDirectStreamP95(1_400))
        #expect(!ProviderLatencyVerdict.meetsDirectStreamP95(1_401))
        #expect(ProviderLatencyVerdict.meetsFirstAudioP50(ProviderLatencyVerdict.firstAudioP50Ms))
        #expect(!ProviderLatencyVerdict.meetsFirstAudioP50(ProviderLatencyVerdict.firstAudioP50Ms + 1))
        #expect(!VoiceProviderKeyPolicy.accepts("1234567"))
        #expect(VoiceProviderKeyPolicy.accepts("12345678"))
        #expect(!VoiceProviderKeyPolicy.accepts("1234 6789"))
    }

    private func ready(_ harness: JourneyHarness, _ id: String, _ secret: String) async {
        await harness.session.saveKey(providerID: id, key: secret)
    }

    private func record(_ ms: Int) {
        guard let path = ProcessInfo.processInfo.environment["ZEUS_E2E_LATENCY_LOG"], !path.isEmpty else { return }
        let line = "\(ms)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }

    private func assertNoSecret(_ harness: JourneyHarness) {
        let log = harness.logBox.text
        #expect(!log.contains(key))
        #expect(!log.contains(other))
        #expect(!log.contains("zeus-e2e"))
    }

    private func legalChange(_ before: ProviderReadiness, _ event: ProviderReadinessEvent, _ after: ProviderReadiness) -> Bool {
        switch (before, event, after) {
        case (.validating, .validationSucceeded, .ready): true
        case (.validating, .validationFailed(let reason), .error(let got)) where reason == got: true
        case (.ready, .runtimeFailure(let reason), .error(let got)) where reason == got: true
        default: false
        }
    }
}

private struct E2ESplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private extension ProviderReadinessEvent {
    static var allProbe: [ProviderReadinessEvent] {
        [.saveCredential, .validationStarted, .validationSucceeded, .validationFailed(.unauthorized),
         .validationFailed(.timedOut), .remove, .runtimeFailure(.server(500)), .runtimeFailure(.offline), .retry]
    }
}

private struct JourneyHarness {
    let store = MemoryCredentialStore()
    let transport = JourneyTransport()
    let local: CountingLocal
    let system = CountingSystem()
    let logBox = JourneyLog()
    let signposter = ProviderSignposter()
    let preferences: VoiceProviderPreferences
    let session: VoiceProviderSession
    var log: ProviderLog { ProviderLog { [logBox] line in logBox.add(line) } }

    init(localEmpty: Bool = false) throws {
        let suite = NSTemporaryDirectory() + "zeus.e2e.providers.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        preferences = VoiceProviderPreferences(defaults: defaults)
        local = CountingLocal(empty: localEmpty)
        let box = logBox
        session = VoiceProviderSession(store: store, transport: transport, local: local,
                                       preferences: preferences, log: ProviderLog { box.add($0) },
                                       signposter: signposter, system: system,
                                       firstAudioBudgetMs: 30_000)
    }
}

private final class CountingLocal: LocalVoiceSpeaking, @unchecked Sendable {
    let empty: Bool
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(empty: Bool) { self.empty = empty }
    func speak(_ text: String) async -> Data {
        note()
        return empty ? Data() : Data("local-voice".utf8)
    }
    private func note() { lock.lock(); count += 1; lock.unlock() }
}

private final class CountingSystem: SystemSpeechSpeaking, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func speak(_ text: String) async -> Data {
        note()
        return Data("mac-voice".utf8)
    }
    private func note() { lock.lock(); count += 1; lock.unlock() }
}

private final class JourneyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
}

private extension ProviderHTTPRequest {
    func httpBodyContains(_ needle: String) -> Bool {
        guard let body, let text = String(data: body, encoding: .utf8) else { return false }
        return text.contains(needle)
    }
}

private final class JourneyTransport: ProviderHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [ProviderHTTPRequest] = []
    private var flight = 0
    private var overlap = 0
    var validateStatus = 200
    var speakStatus = 200
    var holdStreams = false
    var offline = false
    var truncate = false
    var invalidAudio = false
    var delayMs = 0
    var requests: [ProviderHTTPRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    var hosts: [String] { requests.compactMap { $0.url.host } }
    var inFlight: Int { lock.lock(); defer { lock.unlock() }; return flight }
    var maxOverlap: Int { lock.lock(); defer { lock.unlock() }; return overlap }

    func send(_ request: ProviderHTTPRequest) async throws -> ProviderHTTPResponse {
        remember(request)
        if offline { throw offlineError() }
        let path = request.url.path
        if path.hasSuffix("/user") { return ProviderHTTPResponse(status: validateStatus, body: Data("{}".utf8)) }
        if path.hasSuffix("/voices") {
            let body: [String: Any] = request.url.host?.contains("googleapis") == true
                ? ["voices": [["name": "zeus.synthetic", "languageCodes": ["en-US"]]]]
                : ["voices": [["voice_id": "zeus.synthetic", "name": "E2E Voice"]]]
            let status = path.contains("texttospeech") ? validateStatus : validateStatus
            return ProviderHTTPResponse(status: status, body: try JSONSerialization.data(withJSONObject: body))
        }
        if path.contains(":synthesize") {
            if speakStatus != 200 { return ProviderHTTPResponse(status: speakStatus, body: Data()) }
            let audio = VoiceProviderFakeAudio.wavSilence().base64EncodedString()
            return ProviderHTTPResponse(status: 200, body: Data("{\"audioContent\":\"\(audio)\"}".utf8))
        }
        return ProviderHTTPResponse(status: 200, body: Data("{}".utf8))
    }

    func stream(_ request: ProviderHTTPRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        remember(request)
        lock.lock()
        flight += 1
        if flight > overlap { overlap = flight }
        lock.unlock()
        let status = speakStatus
        let hold = holdStreams
        let down = offline
        let cut = truncate
        let junk = invalidAudio
        let delay = delayMs
        return AsyncThrowingStream { continuation in
            let task = Task {
                defer { self.endFlight() }
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                if down {
                    continuation.finish(throwing: self.offlineError())
                    return
                }
                if hold {
                    while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
                    continuation.finish(throwing: ProviderFailure.cancelled)
                    return
                }
                continuation.yield(.status(status))
                guard (200...299).contains(status) else {
                    continuation.finish()
                    return
                }
                if junk {
                    continuation.yield(.chunk(Data("NOPE".utf8)))
                    continuation.finish()
                    return
                }
                let wav = VoiceProviderFakeAudio.wavSilence()
                if cut {
                    continuation.yield(.chunk(Data(wav.prefix(8))))
                    continuation.finish(throwing: ProviderFailure.invalidResponse)
                    return
                }
                continuation.yield(.chunk(wav))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func remember(_ request: ProviderHTTPRequest) {
        lock.lock(); seen.append(request); lock.unlock()
    }

    private func endFlight() {
        lock.lock(); flight = max(0, flight - 1); lock.unlock()
    }

    private func offlineError() -> NSError {
        NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    }
}
