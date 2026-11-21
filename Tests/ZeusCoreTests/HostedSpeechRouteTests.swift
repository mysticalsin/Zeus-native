import Foundation
import Testing
@testable import ZeusCore

/// Counts hosted-speech requests. A disabled route must not touch it.
final class HostedSpeechCountingProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var starts = 0

    static func reset() {
        lock.lock()
        starts = 0
        lock.unlock()
    }

    static func started() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.starts += 1
        Self.lock.unlock()
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite struct HostedSpeechRouteTests {
    private let token = "hosted-speech-test-token"

    private func suite() -> UserDefaults {
        let name = "zeus.hosted-speech.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostedSpeechCountingProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func defaultsOffAndMakesNoRequest() {
        HostedSpeechCountingProtocol.reset()
        let defaults = suite()
        var log: [String] = []
        let phase = HostedSpeechClient(session: session()).perform(
            enabled: HostedSpeechPreference.isEnabled(defaults),
            rawURL: "https://speech.example/v1",
            token: token,
            log: &log
        )
        #expect(HostedSpeechPreference.isEnabled(defaults) == false)
        #expect(phase == .off)
        #expect(HostedSpeechCountingProtocol.started() == 0)
        #expect(log == ["hosted speech off"])
    }

    @Test func enabledHttpsRouteMakesOneStubbedRequest() {
        HostedSpeechCountingProtocol.reset()
        var log: [String] = []
        let phase = HostedSpeechClient(session: session()).perform(
            enabled: true,
            rawURL: "https://speech.example/v1",
            token: token,
            log: &log
        )
        guard case .ready(let url) = phase else {
            Issue.record("expected a ready route")
            return
        }
        #expect(url.scheme == "https")
        #expect(url.host == "speech.example")
        #expect(HostedSpeechCountingProtocol.started() == 1)
        #expect(log == ["hosted speech ready speech.example"])
    }

    @Test func urlMustBeHttps() {
        for raw in ["http://speech.example/v1", "file:///tmp/speech", "ftp://speech.example/v1", "speech.example", "", "   ", "https://", "https:///missing"] {
            let phase = HostedSpeechGate.phase(enabled: true, rawURL: raw, token: token)
            #expect(phase == .refused(.notHTTPS), "\(raw) should be refused")
        }
        let missing = HostedSpeechGate.phase(enabled: true, rawURL: nil, token: token)
        #expect(missing == .refused(.missingURL))
    }

    @Test func tokenInsideTheAddressIsRefused() {
        let phase = HostedSpeechGate.phase(
            enabled: true,
            rawURL: "https://speech.example/\(token)",
            token: token
        )
        #expect(phase == .refused(.tokenEmbeddedInURL))
    }

    @Test func missingTokenIsRefusedAndDoesNotCall() {
        HostedSpeechCountingProtocol.reset()
        var log: [String] = []
        let phase = HostedSpeechClient(session: session()).perform(
            enabled: true,
            rawURL: "https://speech.example/v1",
            token: "   ",
            log: &log
        )
        #expect(phase == .refused(.missingToken))
        #expect(HostedSpeechCountingProtocol.started() == 0)
    }

    @Test func tokenStaysInTheSecretStore() {
        let defaults = suite()
        var store = HostedSpeechMemoryStore()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("zeus-hosted-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let phase = HostedSpeechSetup.save(
            url: "https://speech.example/v1",
            token: token,
            store: &store,
            defaults: defaults,
            directory: directory
        )
        #expect(phase == .off)
        #expect(store.read(HostedSpeechAccounts.token) == token)
        #expect(store.read(HostedSpeechAccounts.url) == "https://speech.example/v1")
        let dumped = defaults.dictionaryRepresentation().values.map { "\($0)" }.joined(separator: "\n")
        #expect(!dumped.contains(token))
        #expect(defaults.object(forKey: HostedSpeechAccounts.token) == nil)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? ["unreadable"]
        #expect(files.isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func logsNeverContainTheToken() {
        var log: [String] = []
        _ = HostedSpeechClient(session: session()).perform(enabled: false, rawURL: "https://speech.example/\(token)", token: token, log: &log)
        _ = HostedSpeechClient(session: session()).perform(enabled: true, rawURL: "https://speech.example/v1", token: token, log: &log)
        _ = HostedSpeechClient(session: session()).perform(enabled: true, rawURL: "http://speech.example/v1", token: token, log: &log)
        _ = HostedSpeechClient(session: session()).perform(enabled: true, rawURL: "https://user:\(token)@speech.example/v1", token: token, log: &log)
        let joined = log.joined(separator: "\n")
        #expect(!joined.contains(token))
        #expect(!joined.contains("Bearer"))
        #expect(HostedSpeechLog.line(phase: .ready(URL(string: "https://speech.example/v1")!), host: "speech.example").contains(token) == false)
    }
}
