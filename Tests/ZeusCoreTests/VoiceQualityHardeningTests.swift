import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Testing
@testable import ZeusCore

/// Production transport, meter collision, and keychain accessibility. No network.
@Suite("Voice quality hardening", .serialized)
struct VoiceQualityHardeningTests {
    @Test func productionTransportRefusesARedirect() async throws {
        ProductionRedirectStub.reset()
        let transport = VoiceQualityURLSessionTransport(timeout: 2, protocolClasses: [ProductionRedirectStub.self])
        let sentinel = "redirect-sentinel-key-66bb"
        let request = ProviderHTTPRequest(
            url: URL(string: "https://api.elevenlabs.io/v1/user")!,
            method: "GET",
            headers: ["xi-api-key": sentinel],
            body: nil
        )
        await #expect(throws: VoiceQualityError.endpointRefused) {
            try await transport.send(request)
        }
        #expect(ProductionRedirectStub.hosts == ["api.elevenlabs.io"])
        #expect(!ProductionRedirectStub.hosts.contains("collector.example"))
        #expect(ProductionRedirectStub.foreignKeys.isEmpty)
    }

    @Test func anExclusiveTemporaryNameCollisionLeavesTheFileUntouched() throws {
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        meter.testingTemporaryName = "fixed.tmp"
        let temporary = directory.appendingPathComponent("fixed.tmp")
        try Data("KEEP".utf8).write(to: temporary)
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
        #expect(try String(contentsOf: temporary, encoding: .utf8) == "KEEP")
    }

    @Test func aSwappedInodeAfterRenameIsRefused() throws {
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        let file = directory.appendingPathComponent(VoiceQualityMeter.fileName)
        meter.testingBeforeDestinationCheck = { url in
            let replacement = url.deletingLastPathComponent().appendingPathComponent("swapped.json")
            try? Data("swapped".utf8).write(to: replacement)
            _ = rename(replacement.path, url.path)
        }
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "swapped")
    }

    @Test func aParentSyncFailureIsRefused() throws {
        let directory = try temporaryDirectory()
        let meter = try VoiceQualityMeter(directory: directory)
        meter.testingSynchronizeParent = { _ in -1 }
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
    }

    @Test func aFifoIsRefused() throws {
        let directory = try temporaryDirectory()
        let fifo = directory.appendingPathComponent(VoiceQualityMeter.fileName)
        #expect(mkfifo(fifo.path, mode_t(0o600)) == 0)
        let meter = try VoiceQualityMeter(directory: directory)
        #expect(throws: VoiceQualityError.meterCorrupt) {
            try meter.reserve(providerID: ElevenLabsTTSAdapter.id, characters: 1)
        }
    }

    @Test func addAndUpdateQueriesIncludeThisDeviceOnlyAccessibility() {
        let shim = RecordingKeychain()
        shim.updateStatus = KeychainStatus.notFound
        let store = KeychainCredentialStore(client: shim)
        #expect(store.write("abcdefgh", service: "com.zeus.app", account: "elevenlabs.api-key"))
        #expect(shim.updates.contains { $0[KeychainItemFields.accessible] == KeychainItemFields.whenUnlockedThisDeviceOnly })
        #expect(shim.adds.contains { $0[KeychainItemFields.accessible] == KeychainItemFields.whenUnlockedThisDeviceOnly })

        shim.updates.removeAll()
        shim.adds.removeAll()
        shim.updateStatus = KeychainStatus.success
        #expect(store.write("abcdefgh", service: "com.zeus.app", account: "elevenlabs.api-key"))
        #expect(shim.adds.isEmpty)
        #expect(shim.updates.contains { $0[KeychainItemFields.accessible] == KeychainItemFields.whenUnlockedThisDeviceOnly })
    }

    @Test func theFirstReadMigratesAnItemThatHasNoAccessibility() {
        let shim = RecordingKeychain()
        shim.stored = (value: "abcdefgh", accessible: nil)
        shim.updateStatus = KeychainStatus.success
        let store = KeychainCredentialStore(client: shim)
        #expect(store.read(service: "com.zeus.app", account: "google-cloud-tts.api-key") == "abcdefgh")
        #expect(shim.updates.contains { $0[KeychainItemFields.accessible] == KeychainItemFields.whenUnlockedThisDeviceOnly })
        #expect(shim.stored?.accessible == KeychainItemFields.whenUnlockedThisDeviceOnly)
        #expect(shim.stored?.value == "abcdefgh")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-quality-hard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RecordingKeychain: KeychainClient, @unchecked Sendable {
    var updates: [[String: String]] = []
    var adds: [[String: String]] = []
    var stored: (value: String, accessible: String?)?
    var updateStatus: Int32 = KeychainStatus.notFound

    func copy(service: String, account: String) -> KeychainCopy {
        guard let stored else {
            return KeychainCopy(status: KeychainStatus.notFound, value: nil, accessible: nil)
        }
        return KeychainCopy(status: KeychainStatus.success, value: stored.value, accessible: stored.accessible)
    }

    func update(service: String, account: String, attributes: [String: String]) -> Int32 {
        updates.append(attributes)
        if updateStatus == KeychainStatus.success {
            stored = (
                value: attributes[KeychainItemFields.value] ?? stored?.value ?? "",
                accessible: attributes[KeychainItemFields.accessible]
            )
        }
        return updateStatus
    }

    func add(_ attributes: [String: String]) -> Int32 {
        adds.append(attributes)
        stored = (
            value: attributes[KeychainItemFields.value] ?? "",
            accessible: attributes[KeychainItemFields.accessible]
        )
        return KeychainStatus.success
    }

    func delete(service: String, account: String?) -> Int32 { KeychainStatus.success }
}

private final class ProductionRedirectStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seenHosts: [String] = []
    nonisolated(unsafe) private static var seenForeignKeys: [String] = []

    static var hosts: [String] { lock.lock(); defer { lock.unlock() }; return seenHosts }
    static var foreignKeys: [String] { lock.lock(); defer { lock.unlock() }; return seenForeignKeys }

    static func reset() {
        lock.lock()
        seenHosts = []
        seenForeignKeys = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let key = request.value(forHTTPHeaderField: "xi-api-key")
        Self.lock.lock()
        Self.seenHosts.append(host)
        if host != "api.elevenlabs.io", let key { Self.seenForeignKeys.append(key) }
        Self.lock.unlock()
        if host == "collector.example" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let destination = URL(string: "https://collector.example/collect")!
        let redirect = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
        #if os(macOS)
        var followed = URLRequest(url: destination)
        if let key { followed.setValue(key, forHTTPHeaderField: "xi-api-key") }
        client?.urlProtocol(self, wasRedirectedTo: followed, redirectResponse: redirect)
        #else
        client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
        #endif
    }

    override func stopLoading() {}
}
