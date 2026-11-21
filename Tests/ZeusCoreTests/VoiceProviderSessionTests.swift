import Foundation
import Testing
@testable import ZeusCore

@Suite("Voice provider session")
struct VoiceProviderSessionTests {
    private let secret = "sk-live-TESTKEY-998877"
    private let sentence = "zephyr-quota-token"

    @Test func addingAProviderValidatingItAndSpeakingItStaysOnTheProvider() async throws {
        let harness = try Harness()
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: secret)
        let ready = await harness.session.readiness(for: ElevenLabsTTSAdapter.id)
        #expect(ready == .ready)
        #expect(harness.store.read(service: VoiceProviderAccounts.service, account: VoiceProviderAccounts.keyAccount(for: ElevenLabsTTSAdapter.id)) == secret)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        #expect(harness.defaults.string(forKey: "voice.ttsProvider") == VoiceTTSProvider.elevenLabs.rawValue)
        let outcome = await harness.session.speak(sentence)
        guard case .cloud(let id, let voice) = outcome.route else {
            Issue.record("expected the cloud route, got \(outcome.route)")
            return
        }
        #expect(id == ElevenLabsTTSAdapter.id)
        #expect(voice == "voice-1")
        #expect(outcome.audio == VoiceProviderFakeAudio.wavSilence())
        #expect(outcome.signpostName == ProviderSignpostName.firstAudio)
        #expect(outcome.metVoiceLegBudget)
        #expect(outcome.metDirectStreamP95)
        #expect(outcome.firstAudioMs <= ProviderLatencyVerdict.voiceLegMs)
        #expect(outcome.firstAudioMs <= ProviderLatencyVerdict.directStreamP95Ms)
        #expect(ProviderLatencyVerdict.voiceLegMs == 600)
        #expect(ProviderLatencyVerdict.directStreamP50Ms == 900)
        #expect(ProviderLatencyVerdict.directStreamP95Ms == 1_400)
        #expect(!outcome.statusLine.isEmpty)
        #expect(harness.local.calls == 0)
        let posted = harness.transport.requests.contains { $0.httpBodyContains(sentence) }
        #expect(posted)
        let signpost = harness.signposter.samples.last
        #expect(signpost?.name == ProviderSignpostName.firstAudio)
        #expect(signpost?.metadata["route"] == "cloud")
        #expect(signpost?.metadata["provider"] == ElevenLabsTTSAdapter.id)
        #expect(signpost?.metadata["key"] == nil)
        assertSecretIsAbsent(harness)
    }

    @Test func anUnauthorizedProviderFallsBackAndStopsSendingText() async throws {
        let harness = try Harness()
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: secret)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        harness.transport.streamStatus = 401
        let outcome = await harness.session.speak(sentence)
        #expect(outcome.route == .local(.failed(.unauthorized)))
        #expect(harness.local.calls == 1)
        #expect(!harness.local.spoken.joined().isEmpty)
        #expect(await harness.session.readiness(for: ElevenLabsTTSAdapter.id) == .error(.unauthorized))
        #expect(!outcome.statusLine.isEmpty)
        let callsBefore = harness.transport.requests.count
        let again = await harness.session.speak(sentence)
        #expect(again.route == .local(.notReady))
        #expect(harness.transport.requests.count == callsBefore)
        #expect(harness.local.calls == 2)
        assertSecretIsAbsent(harness)
    }

    @Test func aTimeoutARateLimitAndAServerErrorStillSpeakLocally() async throws {
        let timeout = try Harness()
        await timeout.session.saveKey(providerID: GoogleCloudTTSAdapter.id, key: secret)
        await timeout.session.select(.provider(GoogleCloudTTSAdapter.id))
        timeout.transport.streamError = .timedOut
        let timed = await timeout.session.speak(sentence)
        #expect(timed.route == .local(.timedOut))
        #expect(timeout.local.calls == 1)
        #expect(await timeout.session.readiness(for: GoogleCloudTTSAdapter.id) == .ready)
        #expect(!timed.statusLine.isEmpty)

        let limited = try Harness()
        await limited.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: secret)
        await limited.session.select(.provider(ElevenLabsTTSAdapter.id))
        limited.transport.streamStatus = 429
        let rate = await limited.session.speak(sentence)
        #expect(rate.route == .local(.failed(.rateLimited)))
        #expect(await limited.session.readiness(for: ElevenLabsTTSAdapter.id) == .error(.rateLimited))

        let down = try Harness()
        await down.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: secret)
        await down.session.select(.provider(ElevenLabsTTSAdapter.id))
        down.transport.streamStatus = 500
        let server = await down.session.speak(sentence)
        #expect(server.route == .local(.failed(.server(500))))
        #expect(down.local.calls == 1)
        #expect(await down.session.readiness(for: ElevenLabsTTSAdapter.id) == .ready)
    }

    @Test func textStaysOnThisMacUntilTheProviderIsSelectedAndReady() async throws {
        let harness = try Harness()
        let idle = await harness.session.speak(sentence)
        #expect(idle.route == .local(.selected))
        #expect(harness.transport.requests.isEmpty)
        #expect(harness.local.calls == 1)

        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        let unset = await harness.session.speak(sentence)
        #expect(unset.route == .local(.notReady))
        #expect(harness.transport.requests.isEmpty)

        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: secret)
        await harness.session.select(.local)
        let back = await harness.session.speak(sentence)
        #expect(back.route == .local(.selected))
        #expect(!harness.transport.requests.contains { $0.httpBodyContains(sentence) })
    }

    @Test func removingAProviderDeletesItsKeyAndReturnsToTheLocalVoice() async throws {
        let harness = try Harness()
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: secret)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        await harness.session.remove(providerID: ElevenLabsTTSAdapter.id)
        let service = VoiceProviderAccounts.service
        #expect(harness.store.read(service: service, account: VoiceProviderAccounts.keyAccount(for: ElevenLabsTTSAdapter.id)) == nil)
        #expect(await harness.session.choice == .local)
        #expect(await harness.session.readiness(for: ElevenLabsTTSAdapter.id) == .unset)
        let outcome = await harness.session.speak(sentence)
        #expect(outcome.route == .local(.selected))
        #expect(!harness.transport.requests.contains { $0.httpBodyContains(sentence) })
        let domain = harness.defaults.dictionaryRepresentation().description
        #expect(!domain.contains(secret))
        #expect(!domain.contains(sentence))
    }

    @Test func theKeyNeverAppearsInTheLog() async throws {
        let harness = try Harness()
        harness.log.record("status=401 xi-api-key=\(secret)", secrets: [secret])
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: secret)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        _ = await harness.session.speak(sentence)
        assertSecretIsAbsent(harness)
        let card = await harness.session.card()
        #expect(!card.publicText.contains(secret))
        #expect(card.keyIsMasked)
        #expect(card.onboarding.contains("this Mac"))
        #expect(card.helper.contains("selected and ready"))
        #expect(card.metrics.rowHeight == 52)
        #expect(card.metrics.padding == 32)
        #expect(card.metrics.cardGap == 28)
        assertSecretIsAbsent(harness)
    }

    @Test func cancelStopsTheCloudVoiceAndDoesNotFallBack() async throws {
        let harness = try Harness()
        await harness.session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: secret)
        await harness.session.select(.provider(ElevenLabsTTSAdapter.id))
        harness.transport.holdStreams = true
        let session = harness.session
        let task = Task { await session.speak(sentence) }
        try await Task.sleep(for: .milliseconds(30))
        await session.cancel()
        let outcome = await task.value
        #expect(outcome.route == .cancelled)
        #expect(harness.local.calls == 0)
        #expect(!outcome.statusLine.isEmpty)
    }

    private func assertSecretIsAbsent(_ harness: Harness) {
        let log = harness.logBox.text
        #expect(!log.contains(secret))
        #expect(!log.contains(sentence))
    }
}

private final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    func record(_ line: String, secrets: [String]) {
        var safe = line
        for secret in secrets where secret.count >= 4 {
            safe = safe.replacingOccurrences(of: secret, with: "••••")
        }
        lock.lock(); lines.append(safe); lock.unlock()
    }
}

private extension ProviderHTTPRequest {
    func httpBodyContains(_ needle: String) -> Bool {
        guard let body, let text = String(data: body, encoding: .utf8) else { return false }
        return text.contains(needle)
    }
}

private struct Harness {
    let store = MemoryCredentialStore()
    let transport = ScriptedVoiceTransport()
    let local = FakeLocalVoice()
    let logBox = LogCapture()
    let signposter = ProviderSignposter()
    let defaults: UserDefaults
    let session: VoiceProviderSession
    var log: ProviderLog { ProviderLog(sink: { [logBox] line in logBox.record(line, secrets: []) }) }

    init() throws {
        let suite = "zeus.test.voice-providers.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        self.defaults = defaults
        let box = logBox
        let log = ProviderLog { line in box.record(line, secrets: []) }
        session = VoiceProviderSession(
            store: store,
            transport: transport,
            local: local,
            preferences: VoiceProviderPreferences(defaults: defaults),
            log: log,
            signposter: signposter
        )
    }
}

private final class FakeLocalVoice: LocalVoiceSpeaking, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var spoken: [String] = []
    var calls: Int { lock.lock(); defer { lock.unlock() }; return spoken.count }
    func speak(_ text: String) async -> Data {
        remember(text)
        return Data("local-voice".utf8)
    }
    private func remember(_ text: String) {
        lock.lock(); spoken.append(text); lock.unlock()
    }
}

private final class ScriptedVoiceTransport: ProviderHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [ProviderHTTPRequest] = []
    var streamStatus = 200
    var streamError: ProviderFailure?
    var holdStreams = false
    var requests: [ProviderHTTPRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    private func remember(_ request: ProviderHTTPRequest) {
        lock.lock(); seen.append(request); lock.unlock()
    }

    func send(_ request: ProviderHTTPRequest) async throws -> ProviderHTTPResponse {
        remember(request)
        if let streamError { throw streamError }
        let path = request.url.path
        if path.hasSuffix("/user") { return ProviderHTTPResponse(status: 200, body: Data("{}".utf8)) }
        if path.hasSuffix("/voices") || path.hasSuffix("/v1/voices") {
            let body: [String: Any]
            if request.url.host?.contains("googleapis") == true {
                body = ["voices": [["name": "en-US-Neural2-C", "languageCodes": ["en-US"]]]]
            } else {
                body = ["voices": [["voice_id": "voice-1", "name": "One"]]]
            }
            return ProviderHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: body))
        }
        if request.url.path.contains(":synthesize") {
            let audio = VoiceProviderFakeAudio.wavSilence().base64EncodedString()
            let body = try JSONSerialization.data(withJSONObject: ["audioContent": audio])
            return ProviderHTTPResponse(status: streamStatus, body: body)
        }
        return ProviderHTTPResponse(status: 200, body: Data("{}".utf8))
    }

    func stream(_ request: ProviderHTTPRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        remember(request)
        let status = streamStatus
        let error = streamError
        let hold = holdStreams
        return AsyncThrowingStream { continuation in
            if hold {
                continuation.onTermination = { _ in }
                return
            }
            if let error {
                continuation.finish(throwing: error)
                return
            }
            continuation.yield(.status(status))
            if (200...299).contains(status) {
                continuation.yield(.chunk(VoiceProviderFakeAudio.wavSilence()))
            }
            continuation.finish()
        }
    }
}
