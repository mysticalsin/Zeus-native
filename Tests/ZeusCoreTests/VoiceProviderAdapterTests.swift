import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

@Suite("Voice provider adapters", .serialized)
struct VoiceProviderAdapterTests {
    private let elevenKey = "el-test-key-not-a-secret-4f91"
    private let googleKey = "goog-test-key-not-a-secret-4f91"

    @Test func elevenLabsRequestsMatchTheStreamingVoiceAPI() throws {
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        let stream = try #require(ElevenLabsTTSAdapter.streamRequest(text: "Hello there", voiceID: "21m00Tcm4TlvDq8ikWAM", credential: credential))
        #expect(stream.method == "POST")
        #expect(stream.url.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM/stream")
        #expect(stream.header("xi-api-key") == elevenKey)
        #expect(stream.header("Content-Type") == "application/json")
        #expect(stream.header("Accept") == "audio/mpeg")
        let body = try jsonObject(stream.body)
        #expect(body["text"] as? String == "Hello there")
        #expect(body["model_id"] as? String == "eleven_flash_v2_5")
        #expect(!stream.url.absoluteString.contains(elevenKey))

        let voices = try #require(ElevenLabsTTSAdapter.voicesRequest(credential: credential))
        #expect(voices.method == "GET")
        #expect(voices.url.absoluteString == "https://api.elevenlabs.io/v1/voices")
        #expect(voices.header("xi-api-key") == elevenKey)
        #expect(voices.body == nil)

        let user = try #require(ElevenLabsTTSAdapter.validationRequest(credential: credential))
        #expect(user.method == "GET")
        #expect(user.url.absoluteString == "https://api.elevenlabs.io/v1/user")
        #expect(user.header("xi-api-key") == elevenKey)
        #expect(ElevenLabsTTSAdapter.streamRequest(text: "Hi", voiceID: "../admin", credential: credential) == nil)
        #expect(ElevenLabsTTSAdapter.streamRequest(text: "Hi", voiceID: "voice/id", credential: credential) == nil)
    }

    @Test func googleRequestsUseTheV1SynthesizeAPIAndKeepTheKeyOutOfTheURL() throws {
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: googleKey])
        let voice = ProviderVoice(id: "en-US-Neural2-C", name: "Neural2 C", language: "en-US")
        let call = try #require(GoogleCloudTTSAdapter.synthesizeRequest(text: "Hello there", voice: voice, credential: credential))
        #expect(call.method == "POST")
        #expect(call.url.absoluteString == "https://texttospeech.googleapis.com/v1/text:synthesize")
        #expect(call.header("X-Goog-Api-Key") == googleKey)
        #expect(call.header("Content-Type") == "application/json")
        #expect(call.url.query == nil)
        #expect(!call.url.absoluteString.contains(googleKey))
        let body = try jsonObject(call.body)
        let input = try #require(body["input"] as? [String: Any])
        #expect(input["text"] as? String == "Hello there")
        let voiceBody = try #require(body["voice"] as? [String: Any])
        #expect(voiceBody["name"] as? String == "en-US-Neural2-C")
        #expect(voiceBody["languageCode"] as? String == "en-US")
        let audio = try #require(body["audioConfig"] as? [String: Any])
        #expect(audio["audioEncoding"] as? String == "MP3")

        let voices = try #require(GoogleCloudTTSAdapter.voicesRequest(credential: credential))
        #expect(voices.method == "GET")
        #expect(voices.url.absoluteString == "https://texttospeech.googleapis.com/v1/voices")
        #expect(voices.header("X-Goog-Api-Key") == googleKey)
        #expect(voices.url.query == nil)
        #expect(GoogleCloudTTSAdapter.validationRequest(credential: credential)?.url == voices.url)
    }

    @Test func urlProtocolSeesTheElevenLabsStreamAndYieldsEachChunk() async throws {
        let chunks = [Data("AAAA".utf8), Data("BBBB".utf8)]
        let transport = stubbed(reply: .init(status: 200, chunks: chunks))
        let adapter = ElevenLabsTTSAdapter()
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        let synthesis = try #require(adapter.synthesize(text: "Hello", voice: ProviderVoice(id: "voice-1", name: "One", language: nil), credential: credential, using: transport))
        var audio = Data()
        var pieces = 0
        for try await chunk in synthesis.chunks {
            audio.append(chunk.data)
            pieces += 1
        }
        let expected = chunks.reduce(into: Data()) { $0.append($1) }
        #expect(pieces > 0)
        #expect(audio == expected)
        let request = try #require(ProviderURLStub.requests.first)
        #expect(request.url?.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/voice-1/stream")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == elevenKey)
        #expect(request.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
    }

    @Test func urlProtocolMaps401429ServerAndTimeout() async {
        let adapter = ElevenLabsTTSAdapter()
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        await #expect(throws: ProviderFailure.unauthorized) {
            try await adapter.validate(credential: credential, using: self.stubbed(reply: .init(status: 401)))
        }
        await #expect(throws: ProviderFailure.rateLimited) {
            try await adapter.validate(credential: credential, using: self.stubbed(reply: .init(status: 429)))
        }
        await #expect(throws: ProviderFailure.server(503)) {
            try await adapter.validate(credential: credential, using: self.stubbed(reply: .init(status: 503)))
        }
        await #expect(throws: ProviderFailure.timedOut) {
            try await adapter.validate(credential: credential, using: self.stubbed(reply: .init(status: 200, fail: URLError(.timedOut))))
        }
    }

    @Test func googleDecodesTheAudioContentAndRejectsABadKey() async throws {
        let audio = Data([0x49, 0x44, 0x33, 0x04])
        let body = try JSONSerialization.data(withJSONObject: ["audioContent": audio.base64EncodedString()])
        let transport = stubbed(reply: .init(status: 200, body: body))
        let adapter = GoogleCloudTTSAdapter()
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: googleKey])
        let voice = ProviderVoice(id: "en-US-Neural2-C", name: "Neural2 C", language: "en-US")
        let synthesis = try #require(adapter.synthesize(text: "Hello", voice: voice, credential: credential, using: transport))
        var got = Data()
        for try await chunk in synthesis.chunks { got.append(chunk.data) }
        #expect(got == audio)
        let request = try #require(ProviderURLStub.requests.first)
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == googleKey)
        let address = request.url?.absoluteString ?? ""
        #expect(address.contains(googleKey) == false)

        await #expect(throws: ProviderFailure.unauthorized) {
            try await adapter.validate(credential: credential, using: self.stubbed(reply: .init(status: 401)))
        }
    }

    @Test func aRedirectNeverCarriesTheKeyToASecondHost() async throws {
        let key = "redirect-probe-key-4f91"
        let originalURL = try #require(URL(string: "https://api.elevenlabs.io/v1/user"))
        let otherURL = try #require(URL(string: "https://collector.example/collect"))
        var proposed = URLRequest(url: otherURL)
        proposed.setValue(key, forHTTPHeaderField: "xi-api-key")
        proposed.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        let delegate = ProviderHTTPSessionDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URLRequest(url: originalURL))
        defer { task.cancel() }
        let redirect = HTTPURLResponse(url: originalURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": otherURL.absoluteString])!
        let decision = RedirectDecision()
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: redirect, newRequest: proposed) { decision.record($0) }
        let fake = RedirectHostFake()
        fake.receive(host: originalURL.host ?? "", xi: key, goog: key)
        if let followed = decision.request {
            fake.receive(host: followed.url?.host?.lowercased() ?? "", xi: followed.value(forHTTPHeaderField: "xi-api-key"), goog: followed.value(forHTTPHeaderField: "X-Goog-Api-Key"))
        }
        let forwarded = decision.request != nil
        let reachedSecondHost = fake.hits.contains { $0.host == "collector.example" }
        let carriedCredential = fake.hits.contains { $0.host != "api.elevenlabs.io" && ($0.xi != nil || $0.goog != nil) }
        #expect(decision.called)
        #expect(!forwarded)
        #expect(!reachedSecondHost)
        #expect(!carriedCredential)

        RedirectProbe.reset()
        let lines = RedirectLog()
        let transport = URLSessionProviderTransport(protocolClasses: [RedirectProbe.self], timeout: 2, log: ProviderLog { lines.add($0) })
        let request = ProviderHTTPRequest(url: originalURL, method: "GET", headers: ["xi-api-key": key, "X-Goog-Api-Key": key], body: nil)
        _ = try? await transport.send(request)
        let seen = RedirectProbe.snapshot()
        #expect(seen.contains { $0.host == "api.elevenlabs.io" })
        #expect(!seen.contains { $0.host == "collector.example" })
        #expect(!seen.contains { $0.host != "api.elevenlabs.io" && ($0.xi != nil || $0.goog != nil) })
        #expect(!lines.text.contains(key))
    }

    @Test func plainHTTPNeverLeavesTheMachine() async {
        let transport = URLSessionProviderTransport(protocolClasses: [ProviderURLStub.self], timeout: 2)
        ProviderURLStub.reset(reply: .init(status: 200, chunks: [Data([1])]))
        let request = ProviderHTTPRequest(url: URL(string: "http://api.elevenlabs.io/v1/user")!, method: "GET", headers: [:], body: nil)
        await #expect(throws: ProviderFailure.notHTTPS) {
            _ = try await transport.send(request)
        }
        #expect(ProviderURLStub.requests.isEmpty)
        #expect(ProviderHTTPBudget.requestTimeout == 8)
        #expect(ProviderHTTPBudget.requestTimeout != 20)
        #expect(ProviderHTTPBudget.requestTimeout != 45)
    }

    private func stubbed(reply: ProviderURLStub.Reply) -> URLSessionProviderTransport {
        ProviderURLStub.reset(reply: reply)
        return URLSessionProviderTransport(protocolClasses: [ProviderURLStub.self], timeout: 2)
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])
    }
}

final class ProviderURLStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var chunks: [Data] = []
        var body: Data?
        var fail: URLError?
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
        if let fail = reply.fail {
            client?.urlProtocol(self, didFailWithError: fail)
            return
        }
        let headers = reply.headers
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://example.invalid/")!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let pieces = reply.body.map { [$0] } ?? reply.chunks
        for piece in pieces { client?.urlProtocol(self, didLoad: piece) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class RedirectDecision: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    private var didCall = false
    var called: Bool { lock.lock(); defer { lock.unlock() }; return didCall }
    var request: URLRequest? { lock.lock(); defer { lock.unlock() }; return stored }
    func record(_ request: URLRequest?) { lock.lock(); didCall = true; stored = request; lock.unlock() }
}

private final class RedirectHostFake {
    struct Hit { var host: String; var xi: String?; var goog: String? }
    private(set) var hits: [Hit] = []
    func receive(host: String, xi: String?, goog: String?) { hits.append(Hit(host: host, xi: xi, goog: goog)) }
}

private final class RedirectLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
}

/// First host answers with a redirect. A second host records whatever headers arrive.
final class RedirectProbe: URLProtocol, @unchecked Sendable {
    struct Hit: Equatable {
        var host: String
        var xi: String?
        var goog: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Hit] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        seen = []
    }

    static func snapshot() -> [Hit] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme?.lowercased() == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host?.lowercased() ?? ""
        let hit = Hit(host: host, xi: request.value(forHTTPHeaderField: "xi-api-key"), goog: request.value(forHTTPHeaderField: "X-Goog-Api-Key"))
        Self.lock.lock()
        Self.seen.append(hit)
        Self.lock.unlock()
        guard host == "api.elevenlabs.io" || host == "texttospeech.googleapis.com" else {
            let response = HTTPURLResponse(url: request.url ?? URL(string: "https://collector.example/")!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let target = URL(string: "https://collector.example/collect")!
        let response = HTTPURLResponse(url: request.url ?? target, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
