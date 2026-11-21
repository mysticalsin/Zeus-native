import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

/// Persona route gate and the security sweep for quality presets. No network.
@Suite("Voice quality route and security", .serialized)
struct VoiceQualityRouteSecurityTests {
    private let elevenKey = "route-eleven-key-9911"
    private let googleKey = "route-google-key-9911"

    @Test func automaticStaysSyntheticEvenWhenEveryKeyAndPresetAreSet() async throws {
        let keys = PersonaSpeakKeys(elevenLabs: true, openAI: true, gemini: true, googleCloud: true, kokoroReady: true)
        let selection = VoiceQualityRoute.selection(choice: .automatic, keys: keys, preset: .elevenLabsStudio)
        #expect(selection == .synthetic)
        #expect(VoiceQualityRoute.activeVoiceID(choice: .automatic, keys: keys, preset: .elevenLabsStudio) == "zeus.synthetic")
        #expect(VoiceQualityRoute.activeVoiceID(choice: .automatic, keys: keys, preset: .elevenLabsStudio) == PersonaSyntheticVoice.voiceID)
        let seen = try await speak(choice: .automatic, keys: keys, preset: .elevenLabsStudio, credential: elevenKey)
        #expect(seen.hosts.isEmpty)
        #expect(seen.error as? VoiceQualityError == .providerOff)
    }

    @Test func aSelectedProviderWithoutAKeyDoesNotCallTheCloud() async throws {
        let keys = PersonaSpeakKeys(elevenLabs: false, googleCloud: false, kokoroReady: true)
        #expect(VoiceQualityRoute.selection(choice: .elevenLabs, keys: keys, preset: .elevenLabsStudio) == .synthetic)
        #expect(VoiceQualityRoute.selection(choice: .googleCloud, keys: keys, preset: .googleNeural2) == .synthetic)
        let seen = try await speak(choice: .elevenLabs, keys: keys, preset: .elevenLabsStudio, credential: elevenKey)
        #expect(seen.hosts.isEmpty)
        #expect(seen.error as? VoiceQualityError == .providerOff)
    }

    @Test func elevenLabsPresetRunsOnlyWhenThatProviderIsSelectedAndHasAKey() async throws {
        let keys = PersonaSpeakKeys(elevenLabs: true, googleCloud: true, kokoroReady: true)
        #expect(VoiceQualityRoute.selection(choice: .elevenLabs, keys: keys, preset: .elevenLabsStudio) == .preset(.elevenLabsStudio))
        #expect(VoiceQualityRoute.selection(choice: .elevenLabs, keys: keys, preset: .googleNeural2) == .synthetic)
        #expect(VoiceQualityRoute.selection(choice: .elevenLabs, keys: keys, preset: .elevenLabsStudio, providerFailed: true) == .synthetic)
        let seen = try await speak(choice: .elevenLabs, keys: keys, preset: .elevenLabsStudio, credential: elevenKey, status: 200, body: Data([0x49, 0x44, 0x33, 0x04]))
        #expect(seen.hosts == ["api.elevenlabs.io"])
        #expect(seen.error == nil)
        let mismatch = try await speak(choice: .elevenLabs, keys: keys, preset: .googleNeural2, credential: googleKey)
        #expect(mismatch.hosts.isEmpty)
    }

    @Test func googlePresetRunsOnlyWhenThatProviderIsSelectedAndHasAKey() async throws {
        let keys = PersonaSpeakKeys(elevenLabs: true, googleCloud: true)
        #expect(VoiceQualityRoute.selection(choice: .googleCloud, keys: keys, preset: .googleNeural2) == .preset(.googleNeural2))
        #expect(VoiceQualityRoute.activeVoiceID(choice: .googleCloud, keys: keys, preset: nil) == "zeus.synthetic")
        let audio = Data([0x49, 0x44, 0x33, 0x04])
        let body = try JSONSerialization.data(withJSONObject: ["audioContent": audio.base64EncodedString()])
        let seen = try await speak(choice: .googleCloud, keys: keys, preset: .googleNeural2, credential: googleKey, status: 200, body: body)
        #expect(seen.hosts == ["texttospeech.googleapis.com"])
        #expect(seen.error == nil)
    }

    @Test func newlineKeyIsRejectedBeforeTheMeterAndTheErrorOmitsBothHalves() async throws {
        let head = "newline-head-7f3a"
        let tail = "newline-tail-9c21"
        let key = head + "\n" + tail
        let outcome = try await rejectedKey(key)
        #expect(outcome.error as? VoiceQualityError == .keyRejected)
        #expect(outcome.message == VoiceQualityKeyGate.rejectedMessage)
        #expect(outcome.message == "The key is not valid.")
        #expect(!outcome.message.contains(head))
        #expect(!outcome.message.contains(tail))
        #expect(!outcome.message.contains("\n"))
        #expect(outcome.count == 0)
        #expect(outcome.hosts.isEmpty)
    }

    @Test func crlfKeyIsRejectedBeforeTheMeterAndTheErrorOmitsBothHalves() async throws {
        let head = "crlf-head-4410"
        let tail = "crlf-tail-8821"
        let key = head + "\r\n" + tail
        let outcome = try await rejectedKey(key)
        #expect(outcome.error as? VoiceQualityError == .keyRejected)
        #expect(outcome.message == "The key is not valid.")
        #expect(!outcome.message.contains(head))
        #expect(!outcome.message.contains(tail))
        #expect(!outcome.message.contains("\r"))
        #expect(!outcome.message.contains("\n"))
        #expect(outcome.count == 0)
        #expect(outcome.hosts.isEmpty)
    }

    @Test func tabAndNullKeysAreRejectedWithTheSameFixedMessage() async throws {
        for key in ["tab-head-1100\ttab-tail-2200", "null-head-3300\u{0}null-tail-4400"] {
            let outcome = try await rejectedKey(key)
            #expect(outcome.error as? VoiceQualityError == .keyRejected)
            #expect(outcome.message == "The key is not valid.")
            #expect(!outcome.message.contains("tab-head-1100"))
            #expect(!outcome.message.contains("tab-tail-2200"))
            #expect(!outcome.message.contains("null-head-3300"))
            #expect(!outcome.message.contains("null-tail-4400"))
            #expect(outcome.count == 0)
        }
    }

    @Test func urlSessionAndHeaderErrorsDoNotEchoTheKey() {
        let sentinel = "header-sentinel-key-55aa"
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorBadServerResponse,
            userInfo: [
                NSLocalizedDescriptionKey: "header xi-api-key \(sentinel) failed",
                "xi-api-key": sentinel,
            ]
        )
        let name = VoiceQualityError.publicName(underlying)
        let described = String(describing: VoiceQualityError.publicError(underlying))
        #expect(!name.contains(sentinel))
        #expect(!described.contains(sentinel))
        #expect(!name.contains("xi-api-key"))
        #expect(VoiceQualityEndpoint.allows(URL(string: "https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL/stream")!))
        #expect(VoiceQualityEndpoint.allows(URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize")!))
        #expect(!VoiceQualityEndpoint.allows(URL(string: "https://collector.example/collect")!))
        #expect(!VoiceQualityEndpoint.allows(URL(string: "http://api.elevenlabs.io/v1/user")!))
        #expect(VoiceQualityRequestSize.limit == 5_000)
        #expect(VoiceQualityRequestSize.allows(5_000))
        #expect(!VoiceQualityRequestSize.allows(5_001))
    }

    @Test func aRedirectToAnotherHostIsRefusedAndDropsTheKey() async throws {
        let sentinel = "redirect-sentinel-key-66bb"
        RouteRedirectStub.reset()
        let delegate = VoiceQualityRedirectDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RouteRedirectStub.self]
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user")!)
        request.setValue(sentinel, forHTTPHeaderField: "xi-api-key")
        request.setValue(sentinel, forHTTPHeaderField: "X-Goog-Api-Key")
        _ = try? await session.data(for: request)
        let hosts = RouteRedirectStub.hosts
        #expect(hosts.contains("api.elevenlabs.io"))
        #expect(!hosts.contains("collector.example"))
        let carried = RouteRedirectStub.requests.contains { request in
            let host = request.url?.host ?? ""
            let xi = request.value(forHTTPHeaderField: "xi-api-key")
            let goog = request.value(forHTTPHeaderField: "X-Goog-Api-Key")
            return host != "api.elevenlabs.io" && (xi == sentinel || goog == sentinel)
        }
        #expect(!carried)
        #expect(RouteRedirectStub.forwarded == nil)

        let keys = PersonaSpeakKeys(elevenLabs: true)
        let seen = try await speak(choice: .elevenLabs, keys: keys, preset: .elevenLabsFast, credential: sentinel, status: 302, location: "https://collector.example/collect")
        #expect(!seen.hosts.contains("collector.example"))
        #expect(!seen.log.contains(sentinel))
    }

    @Test func theMeterDoesNotFollowASymlink() throws {
        let directory = try temporaryDirectory()
        let target = directory.appendingPathComponent("real-meter.json")
        let link = directory.appendingPathComponent("voice-quality-meter.json")
        try Data("{\"elevenlabs\":10}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let meter = try VoiceQualityMeter(directory: directory)
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
        #expect(try Data(contentsOf: target) == Data("{\"elevenlabs\":10}".utf8))
    }

    @Test func oneRequestCannotExceedFiveThousandCharacters() async throws {
        let keys = PersonaSpeakKeys(elevenLabs: true)
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        RouteHostStub.reset(reply: .init(status: 200, body: Data([0x49, 0x44, 0x33, 0x04])))
        let speaker = VoiceQualitySpeaker(
            meter: meter,
            transport: URLSessionProviderTransport(protocolClasses: [RouteHostStub.self], timeout: 2)
        )
        let synthesis = speaker.synthesize(
            text: String(repeating: "a", count: 5_001),
            choice: .elevenLabs,
            keys: keys,
            preset: .elevenLabsFast,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        )
        let error = await firstError(synthesis)
        #expect(error as? VoiceQualityError == .requestTooLarge)
        #expect(try meter.count(providerID: ElevenLabsTTSAdapter.id) == 0)
        #expect(RouteHostStub.hosts.isEmpty)
    }

    @Test func concurrentReservesCannotPassTheCapTogether() throws {
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        let group = DispatchGroup()
        let box = ResultBox()
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                do {
                    try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 30_000)
                    box.add(true)
                } catch {
                    box.add(false)
                }
                group.leave()
            }
        }
        group.wait()
        #expect(box.successes == 1)
        #expect(try meter.count(providerID: ElevenLabsTTSAdapter.id) == 30_000)
    }

    private func speak(choice: PersonaSpeakChoice, keys: PersonaSpeakKeys, preset: VoiceQualityPreset?, credential: String, status: Int = 401, body: Data? = nil, location: String? = nil) async throws -> RouteOutcome {
        RouteHostStub.reset(reply: .init(status: status, body: body, location: location))
        let directory = try temporaryDirectory()
        let lines = RouteLog()
        let speaker = VoiceQualitySpeaker(
            meter: try VoiceQualityMeter(directory: directory),
            transport: URLSessionProviderTransport(protocolClasses: [RouteHostStub.self], timeout: 2),
            log: ProviderLog { lines.add($0) }
        )
        let synthesis = speaker.synthesize(
            text: "Hello",
            choice: choice,
            keys: keys,
            preset: preset,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: credential])
        )
        let error = await firstError(synthesis)
        return RouteOutcome(hosts: RouteHostStub.hosts, error: error, log: lines.text)
    }

    private func rejectedKey(_ key: String) async throws -> RejectedKey {
        RouteHostStub.reset(reply: .init(status: 200, body: Data([0x49, 0x44, 0x33, 0x04])))
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        let lines = RouteLog()
        let speaker = VoiceQualitySpeaker(
            meter: meter,
            transport: URLSessionProviderTransport(protocolClasses: [RouteHostStub.self], timeout: 2),
            log: ProviderLog { lines.add($0) }
        )
        let keys = PersonaSpeakKeys(elevenLabs: true)
        let synthesis = speaker.synthesize(
            text: "Hello",
            choice: .elevenLabs,
            keys: keys,
            preset: .elevenLabsFast,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: key])
        )
        let error = await firstError(synthesis)
        let surfaced = error ?? VoiceQualityError.keyRejected
        let message = [String(describing: surfaced), String(reflecting: surfaced), VoiceQualityError.publicName(surfaced), lines.text].joined(separator: "\n")
        return RejectedKey(error: error, message: message, count: try meter.count(providerID: ElevenLabsTTSAdapter.id), hosts: RouteHostStub.hosts)
    }

    private func firstError(_ synthesis: Synthesis) async -> Error? {
        do {
            for try await _ in synthesis.chunks {}
            return nil
        } catch {
            return error
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-quality-route-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct RouteOutcome {
    var hosts: [String]
    var error: Error?
    var log: String
}

private struct RejectedKey {
    var error: Error?
    var message: String
    var count: Int
    var hosts: [String]
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func add(_ value: Bool) { lock.lock(); values.append(value); lock.unlock() }
    var successes: Int { lock.lock(); defer { lock.unlock() }; return values.filter { $0 }.count }
}

private final class RouteLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
}

final class RouteHostStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: Data?
        var location: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var reply = Reply(status: 200)
    nonisolated(unsafe) private static var seen: [String] = []

    static var hosts: [String] {
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
        Self.seen.append(request.url?.host ?? "")
        let reply = Self.reply
        Self.lock.unlock()
        var headers: [String: String] = [:]
        if let location = reply.location { headers["Location"] = location }
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://example.invalid/")!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body = reply.body, !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RouteRedirectStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seenHosts: [String] = []
    nonisolated(unsafe) private static var seenRequests: [URLRequest] = []
    nonisolated(unsafe) static var forwarded: URLRequest?

    static var hosts: [String] { lock.lock(); defer { lock.unlock() }; return seenHosts }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seenRequests }

    static func reset() {
        lock.lock()
        seenHosts = []
        seenRequests = []
        forwarded = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.seenHosts.append(request.url?.host ?? "")
        Self.seenRequests.append(request)
        Self.lock.unlock()
        let host = request.url?.host ?? ""
        if host == "collector.example" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let destination = URL(string: "https://collector.example/collect")!
        var next = URLRequest(url: destination)
        next.setValue(request.value(forHTTPHeaderField: "xi-api-key"), forHTTPHeaderField: "xi-api-key")
        next.setValue(request.value(forHTTPHeaderField: "X-Goog-Api-Key"), forHTTPHeaderField: "X-Goog-Api-Key")
        let redirect = HTTPURLResponse(url: request.url ?? destination, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
        client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: redirect)
    }

    override func stopLoading() {}
}
