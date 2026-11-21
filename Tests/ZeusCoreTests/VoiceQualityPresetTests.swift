import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

/// Quality presets for ElevenLabs and Google Cloud TTS. No network: URLProtocol stubs only.
/// The sentinel key is a fake. A passing run must not print it.
@Suite("Voice quality presets", .serialized)
struct VoiceQualityPresetTests {
    private static let sentinel = "ZEUS_SENTINEL_KEY_7f3a9c"
    private let elevenKey = "el-shape-key-not-secret-4f91"
    private let googleKey = "goog-shape-key-not-secret-4f91"

    @Test func elevenLabsFastRequestMatchesTheStreamEndpoint() throws {
        let request = try elevenRequest(.elevenLabsFast)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL/stream?output_format=pcm_24000")
        #expect(request.header("xi-api-key") == elevenKey)
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.header("Accept") == "audio/pcm")
        #expect(!request.url.absoluteString.contains(elevenKey))
        let body = try jsonObject(request.body)
        #expect(body["text"] as? String == "Hold on, please")
        #expect(body["model_id"] as? String == "eleven_flash_v2_5")
        let settings = try #require(body["voice_settings"] as? [String: Any])
        #expect(close(settings["stability"], 0.45))
        #expect(close(settings["style"], 0))
        #expect(body["ssml"] == nil)
        #expect(!jsonText(request.body).contains("<speak"))
        #expect(!jsonText(request.body).contains("<break"))
    }

    @Test func elevenLabsStudioRequestUsesTheMultilingualModel() throws {
        let request = try elevenRequest(.elevenLabsStudio)
        #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb/stream?output_format=pcm_24000")
        let body = try jsonObject(request.body)
        #expect(body["model_id"] as? String == "eleven_multilingual_v2")
        let settings = try #require(body["voice_settings"] as? [String: Any])
        #expect(close(settings["stability"], 0.6))
        #expect(close(settings["style"], 0.3))
        #expect(body["text"] as? String == "Hold on, please")
    }

    @Test func googleNeural2RequestSetsRatePitchAnd24kLinear16() throws {
        let request = try googleRequest(.googleNeural2)
        expectGoogleShape(request, voice: "en-US-Neural2-D", rate: 0.92, pitch: 0, sendsRate: true)
    }

    @Test func googleWavenetRequestUsesTheOfficialLetterVoice() throws {
        let request = try googleRequest(.googleWavenet)
        expectGoogleShape(request, voice: "en-US-Wavenet-D", rate: 1, pitch: 0, sendsRate: true)
    }

    @Test func googleChirpHDRequestOmitsUnsupportedRateAndPitch() throws {
        let preset = VoiceQualityPreset.googleChirpHD
        #expect(preset.google?.speakingRate == 1)
        #expect(preset.google?.pitch == 0)
        #expect(preset.google?.sendsRateAndPitch == false)
        let request = try googleRequest(.googleChirpHD)
        expectGoogleShape(request, voice: "en-US-Chirp3-HD-Achernar", rate: nil, pitch: nil, sendsRate: false)
    }

    @Test func markupStaysPlainText() throws {
        #expect(VoiceQualityMarkup.spoken("Hold on... please") == "Hold on, please")
        #expect(VoiceQualityMarkup.spoken("a < b & c") == "a < b & c")
        let request = try VoiceQualityRequestBuilder.make(
            text: "a < b & c",
            preset: .googleNeural2,
            voiceID: "en-US-Neural2-D",
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: googleKey])
        )
        let body = try jsonObject(request.body)
        let input = try #require(body["input"] as? [String: Any])
        #expect(input["text"] as? String == "a < b & c")
        #expect(input["ssml"] == nil)
        #expect(!jsonText(request.body).contains("<speak"))
    }

    @Test func descriptionsOmitTheKey() throws {
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        let request = try VoiceQualityRequestBuilder.make(
            text: "Hello",
            preset: .elevenLabsFast,
            voiceID: "EXAVITQu4vr4xnSDxMaL",
            credential: credential
        )
        let call = VoiceQualityCall(request: request)
        #expect(call.description.contains("api.elevenlabs.io"))
        #expect(!call.description.contains(elevenKey))
        #expect(!call.debugDescription.contains(elevenKey))
        #expect(!String(reflecting: call).contains(elevenKey))
        let refused = VoiceQualityError.voiceRefused
        #expect(!String(describing: refused).contains(elevenKey))
        #expect(!String(reflecting: refused).contains(elevenKey))
        #expect(!ProviderFailure.unauthorized.logName.contains(elevenKey))
        #expect(!ProviderFailure.unauthorized.pill.contains(elevenKey))
    }

    @Test func grepFindsNoSentinelInTheLogOrErrorText() async throws {
        let sentinel = Self.sentinel
        let body = Data("{\"detail\":\"\(sentinel)\"}".utf8)
        QualityURLStub.reset(reply: .init(status: 401, body: body))
        let lines = QualityLog()
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        let speaker = VoiceQualitySpeaker(
            meter: meter,
            transport: URLSessionProviderTransport(protocolClasses: [QualityURLStub.self], timeout: 2),
            log: ProviderLog { lines.add($0) }
        )
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: sentinel])
        let synthesis = speaker.synthesize(
            text: "Hello",
            preset: .elevenLabsFast,
            voiceID: "EXAVITQu4vr4xnSDxMaL",
            credential: credential
        )
        var captured = ""
        do {
            for try await chunk in synthesis.chunks {
                captured += String(describing: chunk)
            }
            captured += "ended"
        } catch {
            captured += String(describing: error)
            captured += "\n"
            captured += String(reflecting: error)
        }
        captured += "\n"
        captured += lines.text
        let logURL = directory.appendingPathComponent("sentinel.log")
        try captured.write(to: logURL, atomically: true, encoding: .utf8)
        let status = try grep(sentinel, in: logURL)
        #expect(status == 1)
        let headerMatches = QualityURLStub.requests.first?.value(forHTTPHeaderField: "xi-api-key") == sentinel
        #expect(headerMatches)
        #expect(!captured.contains("<speak"))
    }

    @Test func nonAllowListedVoicesAreRefusedBeforeARequest() async throws {
        let refused = [
            "z9fAnlkpzviPz146aGWa",
            "VR6AewLTigWG4xSOukaG",
            "en-US-Chirp3-HD-Puck",
            "en-US-Chirp3-HD-Fenrir",
            "MCU-Tony",
            "mcu-voice",
            "cloned-voice-001",
            "en-US-Studio-O",
            "zeus.synthetic",
            "../admin",
            "voice/id",
        ]
        for voice in refused {
            #expect(!VoiceQualityAllowList.accepts(voice, providerID: ElevenLabsTTSAdapter.id))
            #expect(!VoiceQualityAllowList.accepts(voice, providerID: GoogleCloudTTSAdapter.id))
            #expect(throws: VoiceQualityError.voiceRefused) {
                try VoiceQualityRequestBuilder.make(
                    text: "Hello",
                    preset: voice.hasPrefix("en-US") ? .googleNeural2 : .elevenLabsFast,
                    voiceID: voice,
                    credential: ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
                )
            }
        }
        #expect(VoiceQualityAllowList.accepts("EXAVITQu4vr4xnSDxMaL", providerID: ElevenLabsTTSAdapter.id))
        #expect(VoiceQualityAllowList.accepts("JBFqnCBsd6RMkjVDRZzb", providerID: ElevenLabsTTSAdapter.id))
        #expect(VoiceQualityAllowList.accepts("en-US-Neural2-D", providerID: GoogleCloudTTSAdapter.id))
        #expect(VoiceQualityAllowList.accepts("en-US-Wavenet-D", providerID: GoogleCloudTTSAdapter.id))
        #expect(VoiceQualityAllowList.accepts("en-US-Chirp3-HD-Achernar", providerID: GoogleCloudTTSAdapter.id))
        #expect(VoiceQualityAllowList.accepts("en-US-Chirp-HD-D", providerID: GoogleCloudTTSAdapter.id))
        #expect(!VoiceQualityAllowList.accepts("en-US-Neural2-D", providerID: ElevenLabsTTSAdapter.id))
        for preset in VoiceQualityPreset.allCases {
            #expect(VoiceQualityAllowList.accepts(preset.defaultVoiceID, providerID: preset.providerID))
        }
        QualityURLStub.reset(reply: .init(status: 200, body: Data()))
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        let speaker = VoiceQualitySpeaker(
            meter: meter,
            transport: URLSessionProviderTransport(protocolClasses: [QualityURLStub.self], timeout: 2)
        )
        let synthesis = speaker.synthesize(
            text: "Hello",
            preset: .elevenLabsFast,
            voiceID: "MCU-Tony",
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        )
        let error = await firstError(synthesis)
        #expect(error as? VoiceQualityError == .voiceRefused)
        #expect(QualityURLStub.requests.isEmpty)
        #expect(try meter.count(providerID: ElevenLabsTTSAdapter.id) == 0)
    }

    @Test func meterAllows49999AndRefuses50000() throws {
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 49_999)
        #expect(try meter.count(providerID: ElevenLabsTTSAdapter.id) == 49_999)
        #expect(throws: VoiceQualityError.meterExceeded) {
            try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
        #expect(try meter.count(providerID: ElevenLabsTTSAdapter.id) == 49_999)
        let reloaded = try VoiceQualityMeter(directory: directory)
        #expect(try reloaded.count(providerID: ElevenLabsTTSAdapter.id) == 49_999)

        let other = try temporaryDirectory()
        let fresh = try VoiceQualityMeter(directory: other)
        #expect(throws: VoiceQualityError.meterExceeded) {
            try fresh.reserve(providerID: GoogleCloudTTSAdapter.id, characters: 50_000)
        }
        #expect(try fresh.count(providerID: GoogleCloudTTSAdapter.id) == 0)
        #expect(VoiceQualityMeter.limit == 50_000)
    }

    @Test func meterPersistsPerProvider() throws {
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 10)
        try meter.reserve(providerID: GoogleCloudTTSAdapter.id, characters: 4)
        let reloaded = try VoiceQualityMeter(directory: directory)
        #expect(try reloaded.count(providerID: ElevenLabsTTSAdapter.id) == 10)
        #expect(try reloaded.count(providerID: GoogleCloudTTSAdapter.id) == 4)
        try reloaded.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        #expect(try reloaded.count(providerID: GoogleCloudTTSAdapter.id) == 4)
    }

    @Test func meterFailsClosedOnCorruptState() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("voice-quality-meter.json")
        try Data("not-json".utf8).write(to: file)
        let garbage = try VoiceQualityMeter(directory: directory)
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try garbage.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
        #expect(try Data(contentsOf: file) == Data("not-json".utf8))

        try Data("{\"elevenlabs\":-1}".utf8).write(to: file)
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try garbage.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
        try Data("{\"elevenlabs\":\"12\"}".utf8).write(to: file)
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try garbage.count(providerID: ElevenLabsTTSAdapter.id)
        }

        QualityURLStub.reset(reply: .init(status: 200, chunks: [Data([0x49, 0x44, 0x33, 0x04])]))
        let speaker = VoiceQualitySpeaker(
            meter: garbage,
            transport: URLSessionProviderTransport(protocolClasses: [QualityURLStub.self], timeout: 2)
        )
        let synthesis = speaker.synthesize(
            text: "Hello",
            preset: .elevenLabsFast,
            voiceID: nil,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        )
        let error = await firstError(synthesis)
        #expect(error as? VoiceQualityError == .meterCorrupt)
        #expect(QualityURLStub.requests.isEmpty)
    }

    @Test func optInDefaultsToTheSyntheticVoice() async throws {
        let defaults = freshDefaults("voice-quality-opt-in-empty")
        #expect(VoiceQualityOptIn.selection(defaults: defaults) == .synthetic)
        #expect(VoiceQualityOptIn.activeVoiceID(defaults: defaults) == "zeus.synthetic")
        #expect(VoiceQualityOptIn.activeVoiceID(defaults: defaults) == VoiceSpeakAllowlist.syntheticID)
        defaults.set(VoiceQualityPreset.elevenLabsStudio.rawValue, forKey: VoiceQualityOptIn.presetKey)
        #expect(VoiceQualityOptIn.selection(defaults: defaults) == .synthetic)
        defaults.set(VoiceTTSProvider.kokoro.rawValue, forKey: VoiceProviderPreferences.selectionKey)
        #expect(VoiceQualityOptIn.selection(defaults: defaults) == .synthetic)
        defaults.set(VoiceTTSProvider.elevenLabs.rawValue, forKey: VoiceProviderPreferences.selectionKey)
        defaults.set(VoiceQualityPreset.googleNeural2.rawValue, forKey: VoiceQualityOptIn.presetKey)
        #expect(VoiceQualityOptIn.selection(defaults: defaults) == .synthetic)
        defaults.set(VoiceQualityPreset.elevenLabsStudio.rawValue, forKey: VoiceQualityOptIn.presetKey)
        #expect(VoiceQualityOptIn.selection(defaults: defaults) == .preset(.elevenLabsStudio))

        QualityURLStub.reset(reply: .init(status: 200, body: Data([0x49, 0x44, 0x33, 0x04])))
        let off = freshDefaults("voice-quality-opt-in-off")
        let speaker = VoiceQualitySpeaker(
            meter: try VoiceQualityMeter(directory: try temporaryDirectory()),
            transport: URLSessionProviderTransport(protocolClasses: [QualityURLStub.self], timeout: 2)
        )
        let synthesis = speaker.synthesizeIfEnabled(
            text: "Hello",
            defaults: off,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        )
        let error = await firstError(synthesis)
        #expect(error as? VoiceQualityError == .providerOff)
        #expect(QualityURLStub.requests.isEmpty)
    }

    @Test func cancellationStopsTheInFlightTask() async throws {
        HangURLStub.reset()
        let speaker = VoiceQualitySpeaker(
            meter: try VoiceQualityMeter(directory: try temporaryDirectory()),
            transport: URLSessionProviderTransport(protocolClasses: [HangURLStub.self], timeout: 2)
        )
        let synthesis = speaker.synthesize(
            text: "Hello",
            preset: .googleNeural2,
            voiceID: nil,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: googleKey])
        )
        let finished = Task { () -> String in
            do {
                for try await _ in synthesis.chunks {}
                return "ended"
            } catch {
                return VoiceQualityError.publicName(error)
            }
        }
        #expect(HangURLStub.waitUntilStarted(timeout: 3))
        synthesis.cancel()
        let name = await finished.value
        #expect(name == ProviderFailure.cancelled.logName)
        #expect(HangURLStub.didStop)
    }

    @Test func http401429And5xxUseTheExistingFallbackOrder() async throws {
        let cases: [(Int, ProviderFailure, Bool)] = [
            (401, .unauthorized, false),
            (429, .rateLimited, false),
            (503, .server(503), true),
        ]
        for (status, failure, staysReady) in cases {
            let plan = VoiceQualityFallback.plan(for: failure)
            #expect(plan.engines == SyntheticFallbackOrder.engines)
            #expect(plan.engines == ["kokoro", "system"])
            #expect(plan.leavesProviderReady == staysReady)

            QualityURLStub.reset(reply: .init(status: status, body: Data("{\"error\":\"no\"}".utf8)))
            let speaker = VoiceQualitySpeaker(
                meter: try VoiceQualityMeter(directory: try temporaryDirectory()),
                transport: URLSessionProviderTransport(protocolClasses: [QualityURLStub.self], timeout: 2)
            )
            let synthesis = speaker.synthesize(
                text: "Hello",
                preset: .googleNeural2,
                voiceID: nil,
                credential: ProviderCredential(fields: [ProviderCredentialLocation.account: googleKey])
            )
            let error = await firstError(synthesis)
            #expect(error as? ProviderFailure == failure)

            let defaults = freshDefaults("voice-quality-fallback-\(status)")
            let session = VoiceProviderSession(
                store: MemoryCredentialStore(),
                transport: URLSessionProviderTransport(timeout: 2),
                local: ScriptedLocal(),
                preferences: VoiceProviderPreferences(defaults: defaults),
                adapters: [ScriptedFailureAdapter(failure)]
            )
            await session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: "test-key-12345678")
            session.select(.provider(ElevenLabsTTSAdapter.id))
            session.chooseVoice(providerID: ElevenLabsTTSAdapter.id, voiceID: VoiceSpeakAllowlist.syntheticID)
            let outcome = await session.speak("Hello")
            #expect(outcome.route == .local(.failed(failure)))
            let readiness = session.readiness(for: ElevenLabsTTSAdapter.id)
            if staysReady {
                #expect(readiness == .ready)
            } else {
                #expect(readiness == .error(failure))
            }
        }
        #expect(ProviderHTTPBudget.requestTimeout == 8)
    }

    private func elevenRequest(_ preset: VoiceQualityPreset) throws -> ProviderHTTPRequest {
        try VoiceQualityRequestBuilder.make(
            text: "Hold on... please",
            preset: preset,
            voiceID: preset.defaultVoiceID,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        )
    }

    private func googleRequest(_ preset: VoiceQualityPreset) throws -> ProviderHTTPRequest {
        try VoiceQualityRequestBuilder.make(
            text: "Hold on... please",
            preset: preset,
            voiceID: preset.defaultVoiceID,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: googleKey])
        )
    }

    private func expectGoogleShape(_ request: ProviderHTTPRequest, voice: String, rate: Double?, pitch: Double?, sendsRate: Bool) {
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://texttospeech.googleapis.com/v1/text:synthesize")
        #expect(request.header("X-Goog-Api-Key") == googleKey)
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.url.query == nil)
        #expect(!request.url.absoluteString.contains(googleKey))
        let body = (try? jsonObject(request.body)) ?? [:]
        let input = body["input"] as? [String: Any]
        #expect(input?["text"] as? String == "Hold on, please")
        #expect(input?["ssml"] == nil)
        let voiceBody = body["voice"] as? [String: Any]
        #expect(voiceBody?["name"] as? String == voice)
        #expect(voiceBody?["languageCode"] as? String == "en-US")
        let audio = body["audioConfig"] as? [String: Any]
        #expect(audio?["audioEncoding"] as? String == "LINEAR16")
        #expect(audio?["sampleRateHertz"] as? Int == 24_000)
        if sendsRate {
            #expect(close(audio?["speakingRate"], rate ?? -1))
            #expect(close(audio?["pitch"], pitch ?? -1))
        } else {
            #expect(audio?["speakingRate"] == nil)
            #expect(audio?["pitch"] == nil)
        }
        #expect(!jsonText(request.body).contains("<speak"))
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])
    }

    private func jsonText(_ data: Data?) -> String {
        String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private func close(_ value: Any?, _ expected: Double) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return abs(number.doubleValue - expected) < 0.000_001
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-quality-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func grep(_ needle: String, in file: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-F", "-q", needle, file.path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func firstError(_ synthesis: Synthesis) async -> Error? {
        do {
            for try await _ in synthesis.chunks {}
            return nil
        } catch {
            return error
        }
    }
}

private final class QualityLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
}

final class QualityURLStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var chunks: [Data] = []
        var body: Data?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var reply = Reply(status: 200)
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    static func reset(reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        self.reply = reply
        seen = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        let reply = Self.reply
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://example.invalid/")!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let pieces = reply.body.map { [$0] } ?? reply.chunks
        for piece in pieces where !piece.isEmpty { client?.urlProtocol(self, didLoad: piece) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class HangURLStub: URLProtocol, @unchecked Sendable {
    private static let started = NSCondition()
    private static var didStartFlag = false
    private static var didStopFlag = false

    static var didStop: Bool {
        started.lock(); defer { started.unlock() }
        return didStopFlag
    }

    static func reset() {
        started.lock()
        didStartFlag = false
        didStopFlag = false
        started.unlock()
    }

    static func waitUntilStarted(timeout: TimeInterval) -> Bool {
        started.lock()
        defer { started.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while !didStartFlag {
            if !started.wait(until: deadline) { return didStartFlag }
        }
        return true
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.started.lock()
        Self.didStartFlag = true
        Self.started.broadcast()
        Self.started.unlock()
    }

    override func stopLoading() {
        Self.started.lock()
        Self.didStopFlag = true
        Self.started.broadcast()
        Self.started.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
}

private struct ScriptedLocal: LocalVoiceSpeaking {
    func speak(_ text: String) async -> Data { Data([0x49, 0x44, 0x33, 0x04]) }
}

private struct ScriptedFailureAdapter: TTSProvider {
    var failure: ProviderFailure
    var descriptor: ProviderDescriptor { ElevenLabsTTSAdapter.descriptor }
    func listVoices(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws -> [ProviderVoice] {
        [ProviderVoice(id: VoiceSpeakAllowlist.syntheticID, name: "Zeus", language: "en")]
    }
    func synthesize(text: String, voice: ProviderVoice, credential: ProviderCredential, using transport: any ProviderHTTPTransport) -> Synthesis? {
        let failure = failure
        let chunks = AsyncThrowingStream<AudioChunk, Error> { continuation in
            continuation.finish(throwing: failure)
        }
        return Synthesis(chunks: chunks, cancel: {})
    }
    func validate(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws {}
}
