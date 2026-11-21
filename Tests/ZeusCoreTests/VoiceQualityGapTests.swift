import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

/// Gaps from the #290 gate. No network: stubs and local files only.
@Suite("Voice quality gate gaps", .serialized)
struct VoiceQualityGapTests {
    private let elevenKey = "gap-eleven-key-9911"
    private let googleKey = "gap-google-key-9911"

    @Test func sevenCharactersAreRejectedAndEightAreAccepted() {
        let seven = String(repeating: "k", count: 7)
        let eight = String(repeating: "k", count: 8)
        #expect(seven.count == 7)
        #expect(eight.count == 8)
        #expect(!VoiceProviderKeyPolicy.accepts(seven))
        #expect(VoiceProviderKeyPolicy.accepts(eight))
        #expect(VoiceQualityKeyGate.accepted(seven) == nil)
        #expect(VoiceQualityKeyGate.accepted(eight) == eight)
    }

    @Test func deleteAndLineSeparatorsAreRejected() {
        #expect(!VoiceProviderKeyPolicy.accepts("abcd\u{7F}efgh"))
        #expect(!VoiceProviderKeyPolicy.accepts("abcd\u{85}efgh"))
        #expect(!VoiceProviderKeyPolicy.accepts("abcd\u{2028}efgh"))
        #expect(VoiceQualityKeyGate.accepted("abcd\u{7F}efgh") == nil)
    }

    @Test func everyC1ControlIsRejected() {
        for value in 0x80...0x9F {
            let scalar = Unicode.Scalar(value)!
            let key = "abcdefgh" + String(scalar)
            #expect(!VoiceProviderKeyPolicy.accepts(key))
            #expect(VoiceQualityKeyGate.accepted(key) == nil)
        }
    }

    @Test func formatCharactersInTheListedRangesAreRejected() {
        var values: [UInt32] = []
        values.append(contentsOf: 0x200B...0x200F)
        values.append(contentsOf: 0x202A...0x202E)
        values.append(contentsOf: 0x2060...0x2064)
        values.append(0xFEFF)
        for value in values {
            let scalar = Unicode.Scalar(value)!
            let key = "abcdefgh" + String(scalar)
            #expect(!VoiceProviderKeyPolicy.accepts(key))
        }
    }

    @Test func theKeyCapIs256UTF8Bytes() {
        let exact = String(repeating: "a", count: 256)
        #expect(exact.utf8.count == 256)
        #expect(VoiceProviderKeyPolicy.accepts(exact))
        let tooManyBytes = String(repeating: "\u{00E1}", count: 129)
        #expect(tooManyBytes.count == 129)
        #expect(tooManyBytes.count < 256)
        #expect(tooManyBytes.utf8.count == 258)
        #expect(!VoiceProviderKeyPolicy.accepts(tooManyBytes))
        #expect(VoiceQualityKeyGate.accepted(tooManyBytes) == nil)
    }

    @Test func aC1KeyIsRefusedBeforeTheMeterAndTheErrorOmitsTheMarker() async throws {
        let marker = "C1MARK7q"
        let key = marker + "\u{80}" + "tailzz"
        let outcome = try await speak(provider: .eleven, text: "Hello", credential: key, status: 200, body: Data([0x49, 0x44, 0x33, 0x04]))
        #expect(outcome.error as? VoiceQualityError == .keyRejected)
        let description = (outcome.error as? VoiceQualityError)?.description ?? ""
        #expect(description == "The key is not valid.")
        #expect(!description.contains(marker))
        #expect(!outcome.message.contains(marker))
        #expect(outcome.count == 0)
        #expect(outcome.hosts.isEmpty)
    }

    @Test func combiningMarksHitThePerRequestCapInUTF8Bytes() async throws {
        let grapheme = "e\u{0301}"
        #expect(grapheme.count == 1)
        #expect(grapheme.utf8.count == 3)
        let text = String(repeating: grapheme, count: 1_667)
        #expect(text.count < VoiceQualityRequestSize.limit)
        #expect(text.utf8.count == 5_001)
        let eleven = try await speak(provider: .eleven, text: text, credential: elevenKey, status: 200, body: Data([0x49, 0x44, 0x33, 0x04]))
        #expect(eleven.error as? VoiceQualityError == .requestTooLarge)
        #expect(eleven.count == 0)
        #expect(eleven.hosts.isEmpty)
        let audio = Data([0x49, 0x44, 0x33, 0x04])
        let googleBody = try JSONSerialization.data(withJSONObject: ["audioContent": audio.base64EncodedString()])
        let google = try await speak(provider: .google, text: text, credential: googleKey, status: 200, body: googleBody)
        #expect(google.error as? VoiceQualityError == .requestTooLarge)
        #expect(google.count == 0)
        #expect(google.hosts.isEmpty)
    }

    @Test func aShortCombiningRequestChargesUTF8BytesForBothProviders() async throws {
        let text = String(repeating: "e\u{0301}", count: 10)
        #expect(text.count == 10)
        #expect(text.utf8.count == 30)
        let audio = Data([0x49, 0x44, 0x33, 0x04])
        let eleven = try await speak(provider: .eleven, text: text, credential: elevenKey, status: 200, body: audio)
        #expect(eleven.error == nil)
        #expect(eleven.count == 30)
        let googleBody = try JSONSerialization.data(withJSONObject: ["audioContent": audio.base64EncodedString()])
        let google = try await speak(provider: .google, text: text, credential: googleKey, status: 200, body: googleBody)
        #expect(google.error == nil)
        #expect(google.count == 30)
    }

    @Test func combiningBytesCannotCrossTheCumulativeCap() async throws {
        let text = String(repeating: "e\u{0301}", count: 10)
        let outcome = try await speak(provider: .eleven, text: text, credential: elevenKey, status: 200, body: Data([0x49, 0x44, 0x33, 0x04]), alreadyUsed: 49_980)
        #expect(outcome.error as? VoiceQualityError == .meterExceeded)
        #expect(outcome.count == 49_980)
        #expect(outcome.hosts.isEmpty)
    }

    @Test func aSymlinkedParentIsRefused() throws {
        let root = try temporaryDirectory()
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let meter = try VoiceQualityMeter(directory: link)
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
        let written = real.appendingPathComponent(VoiceQualityMeter.fileName)
        #expect(!FileManager.default.fileExists(atPath: written.path))
    }

    @Test func aHardLinkIsRefusedAndLeftUnchanged() throws {
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        let file = directory.appendingPathComponent(VoiceQualityMeter.fileName)
        let alias = directory.appendingPathComponent("alias.json")
        let original = Data("{\"elevenlabs\":4}".utf8)
        try original.write(to: file)
        try FileManager.default.linkItem(at: file, to: alias)
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
        #expect(try Data(contentsOf: file) == original)
        #expect(try Data(contentsOf: alias) == original)
    }

    private enum Provider {
        case eleven
        case google
    }

    private struct Outcome {
        var hosts: [String]
        var error: Error?
        var message: String
        var count: Int
    }

    private func speak(provider: Provider, text: String, credential: String, status: Int, body: Data?, alreadyUsed: Int = 0) async throws -> Outcome {
        GapHostStub.reset(reply: .init(status: status, body: body))
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        if alreadyUsed > 0 {
            let id = provider == .eleven ? ElevenLabsTTSAdapter.id : GoogleCloudTTSAdapter.id
            try meter.reserve(providerID: id, characters: alreadyUsed)
        }
        let lines = GapLog()
        let speaker = VoiceQualitySpeaker(
            meter: meter,
            transport: URLSessionProviderTransport(protocolClasses: [GapHostStub.self], timeout: 2),
            log: ProviderLog { lines.add($0) }
        )
        let keys = provider == .eleven ? VoiceQualitySpeakKeys(elevenLabs: true) : VoiceQualitySpeakKeys(googleCloud: true)
        let choice: VoiceQualitySpeakChoice = provider == .eleven ? .elevenLabs : .googleCloud
        let preset: VoiceQualityPreset = provider == .eleven ? .elevenLabsFast : .googleNeural2
        let synthesis = speaker.synthesize(
            text: text,
            choice: choice,
            keys: keys,
            preset: preset,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: credential])
        )
        let error = await firstError(synthesis)
        let surfaced = error ?? VoiceQualityError.providerOff
        let message = [String(describing: surfaced), String(reflecting: surfaced), VoiceQualityError.publicName(surfaced), lines.text].joined(separator: "\n")
        let id = provider == .eleven ? ElevenLabsTTSAdapter.id : GoogleCloudTTSAdapter.id
        return Outcome(hosts: GapHostStub.hosts, error: error, message: message, count: try meter.count(providerID: id))
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-quality-gap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class GapHostStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: Data?
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
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://example.invalid/")!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body = reply.body, !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class GapLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
}
