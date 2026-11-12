import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Testing
@testable import ZeusCore

@Suite("Any LLM endpoint safety")
struct AnyLLMEndpointSafetyTests {
    @Test func credentialBearingURLDraftsAreNeverSerializedToPreferences() throws {
        for address in ["https://synthetic-user:synthetic-password@example.invalid/v1",
                        "synthetic-user:synthetic-password@example.invalid/v1", "https://synthetic-user:synthetic-password@"] {
            let draft = AnyLLMConfig(baseURL: address, model: "gpt-5-mini")
            let stored = draft.configurationForPreferences
            #expect(stored.baseURL.isEmpty)
            #expect(draft.baseURL == address, "The invalid visible draft must remain available to correct")
            #expect(!String(decoding: try JSONEncoder().encode(stored), as: UTF8.self).contains("synthetic-password"))
        }
        let safe = AnyLLMConfig(baseURL: "https://example.invalid/v1", model: "gpt-5-mini")
        #expect(safe.configurationForPreferences == safe)
    }

    @Test func remoteCleartextAndEmbeddedCredentialsNeverProduceRequests() {
        for address in ["http://api.example.invalid/v1", "http://10.0.0.5/v1",
                        "http://localhost.example.invalid/v1", "http://localhost@api.example.invalid/v1",
                        "https://user:password@api.example.invalid/v1"] {
            let config = AnyLLMConfig(baseURL: address, model: "gpt-5-mini")
            #expect(config.request(prompt: "Synthetic private prompt", key: "synthetic-key") == nil)
            #expect(config.streamingRequest(prompt: "Synthetic private prompt", key: "synthetic-key") == nil)
        }
    }

    @Test func secureRemoteAndExactLoopbackRequestsRemainAvailable() throws {
        for address in ["https://api.example.invalid/v1", "http://localhost:11434/v1",
                        "http://127.0.0.1:1234/v1", "http://[::1]:1234/v1"] {
            let config = AnyLLMConfig(baseURL: address, model: "gpt-5-mini")
            let request = try #require(config.request(prompt: "Synthetic prompt", key: "synthetic-key"))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
            #expect(config.streamingRequest(prompt: "Synthetic prompt", key: nil) != nil)
        }
    }

    @Test func transportRejectsUnsafeDirectRequestsBeforeDispatch() async {
        for address in ["http://remote.example.invalid/v1/models", "https://user:password@example.invalid/v1/models"] {
            do {
                _ = try await AnyLLMHTTPTransport.data(for: URLRequest(url: URL(string: address)!))
                Issue.record("Unsafe endpoint was dispatched")
            } catch {
                #expect((error as? URLError)?.code == .unsupportedURL)
            }
        }
    }

    @Test func editsKeysDisconnectAndRejectedValidationRevokeApproval() throws {
        var state = AnyLLMEndpointValidation()
        let firstAttempt = state.begin()
        let first = try #require(firstAttempt)
        #expect(!state.isApproved)
        let duplicateAttempt = state.begin()
        #expect(duplicateAttempt == nil)
        let accepted = state.complete(.passed("Synthetic server"), generation: first)
        #expect(accepted)
        #expect(state.isApproved)
        state.invalidate()
        #expect(!state.isApproved)
        let late = state.complete(.passed("Late previous endpoint"), generation: first)
        #expect(!late)
        let secondAttempt = state.begin()
        let second = try #require(secondAttempt)
        state.invalidate(reason: "Remote cleartext refused")
        let rejected = state.complete(.passed("Late prior check"), generation: second)
        #expect(!rejected)
        #expect(state.state == .failed("Remote cleartext refused"))
        #expect(!state.isApproved)
    }

    @Test func staleResultsCannotCompleteOrDisableTheReplacementCheck() throws {
        var state = AnyLLMEndpointValidation()
        let firstAttempt = state.begin()
        let first = try #require(firstAttempt)
        state.invalidate()
        let secondAttempt = state.begin()
        let second = try #require(secondAttempt)
        let oldSuccess = state.complete(.passed("Old endpoint"), generation: first)
        #expect(!oldSuccess)
        #expect(state.state == .testing)
        let accepted = state.complete(.passed("Current endpoint"), generation: second)
        #expect(accepted)
        let oldFailure = state.complete(.failed("Old failure"), generation: first)
        #expect(!oldFailure)
        #expect(state.isApproved)
        let duplicate = state.complete(.failed("Duplicate completion"), generation: second)
        #expect(!duplicate)
        #expect(state.isApproved)
    }

    @Test func actualHTTPRedirectNeverReceivesPromptOrKeyAtItsDestination() async throws {
        // Binding/listening completes before the fixture is returned. There is no child-startup
        // file race or independent helper lifetime that can expire while Swift Testing is busy.
        let fixture = try LoopbackRedirectFixture()
        defer { fixture.requestStop() }
        do {
            let config = AnyLLMConfig(baseURL: "http://127.0.0.1:\(fixture.port)", model: "gpt-5-mini")
            var request = try #require(config.request(prompt: "Synthetic private prompt", key: "synthetic-key"))
            request.timeoutInterval = 3
            let (_, response) = try await AnyLLMHTTPTransport.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 307)
            #expect(fixture.sourceReceivedPromptAndKey)
            #expect(!fixture.destinationContacted, "Redirect received the original prompt or credential")
            await fixture.close()
        } catch {
            await fixture.close()
            throw error
        }
    }

    @Test func ownedLoopbackReadinessAndRepeatedCleanupDoNotDependOnAChildStartupFile() async throws {
        let fixture = try LoopbackRedirectFixture()
        defer { fixture.requestStop() }
        #expect(fixture.port > 0)
        // A connection can enter the already-listening socket before its worker has run.
        // Stopping also closes a client that never completes its HTTP request.
        let client = try fixture.connect()
        defer { LoopbackRedirectFixture.closeDescriptor(client) }
        async let first: Void = fixture.close()
        async let second: Void = fixture.close()
        _ = await (first, second)
        var readiness = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
        #expect(poll(&readiness, 1, 500) > 0)
        var byte: UInt8 = 0
        #expect(read(client, &byte, 1) <= 0)
        #expect(throws: (any Error).self) {
            let unexpected = try fixture.connect()
            LoopbackRedirectFixture.closeDescriptor(unexpected)
        }
    }
}

/// A real HTTP peer on IPv4 loopback only. Its dedicated worker never occupies Swift's
/// cooperative executor. Readiness is the completed bind/listen; ownership ends by an explicit
/// stop and asynchronous completion, rather than a wall-clock helper expiry.
private final class LoopbackRedirectFixture: @unchecked Sendable {
    let port: UInt16
    private let state: State

    init() throws {
        let descriptor = Self.makeSocket()
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        do {
            guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
                  fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw POSIXError(.EIO) }
            var address = Self.address(port: 0)
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0, listen(descriptor, 4) == 0 else { throw POSIXError(.EIO) }
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
            }
            guard named == 0 else { throw POSIXError(.EIO) }
            port = UInt16(bigEndian: address.sin_port)
            state = State(listener: descriptor, port: port)
        } catch { Self.closeDescriptor(descriptor); throw error }
        let worker = Thread { [state] in state.run() }
        worker.name = "zeus-test-loopback-http"
        worker.start()
    }

    deinit { state.requestStop() }
    var destinationContacted: Bool { state.lock.withLock { state.destination } }
    var sourceReceivedPromptAndKey: Bool { state.lock.withLock { state.sourceReceivedPromptAndKey } }
    func requestStop() { state.requestStop() }
    func close() async {
        await withCheckedContinuation { continuation in state.requestStop { continuation.resume() } }
    }

    func connect() throws -> Int32 {
        guard !state.isStopping else { throw POSIXError(.ECONNREFUSED) }
        let descriptor = Self.makeSocket()
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            Self.closeDescriptor(descriptor); throw POSIXError(.EIO)
        }
        var address = Self.address(port: port)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                #if canImport(Darwin)
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                #else
                Glibc.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                #endif
            }
        }
        guard connected == 0 else { Self.closeDescriptor(descriptor); throw POSIXError(.ECONNREFUSED) }
        return descriptor
    }

    private static func address(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return address
    }
    private static func makeSocket() -> Int32 {
        #if canImport(Darwin)
        socket(AF_INET, SOCK_STREAM, 0)
        #else
        socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
    }
    static func closeDescriptor(_ descriptor: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(descriptor)
        #else
        _ = Glibc.close(descriptor)
        #endif
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        let listener: Int32
        let port: UInt16
        var destination = false
        var sourceReceivedPromptAndKey = false
        private var stopping = false
        private var finished = false
        private var completions: [@Sendable () -> Void] = []
        init(listener: Int32, port: UInt16) { self.listener = listener; self.port = port }
        private var shouldStop: Bool { lock.withLock { stopping } }
        var isStopping: Bool { shouldStop }

        func requestStop(_ completion: (@Sendable () -> Void)? = nil) {
            let settled = lock.withLock { () -> Bool in
                stopping = true
                if !finished, let completion { completions.append(completion) }
                return finished
            }
            if settled { completion?() }
        }

        func run() {
            defer {
                LoopbackRedirectFixture.closeDescriptor(listener)
                let callbacks = lock.withLock { () -> [@Sendable () -> Void] in
                    finished = true
                    let callbacks = completions; completions.removeAll()
                    return callbacks
                }
                callbacks.forEach { $0() }
            }
            while !shouldStop {
                var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                let count = poll(&ready, 1, 25)
                if count < 0 { if errno == EINTR { continue }; return }
                guard count > 0 else { continue }
                guard ready.revents & Int16(POLLIN) != 0 else { return }
                let client = accept(listener, nil, nil)
                guard client >= 0 else { continue }
                serve(client)
                LoopbackRedirectFixture.closeDescriptor(client)
            }
        }

        private func serve(_ client: Int32) {
            guard fcntl(client, F_SETFD, FD_CLOEXEC) == 0,
                  fcntl(client, F_SETFL, O_NONBLOCK) == 0 else { return }
            #if canImport(Darwin)
            var noSignal: Int32 = 1
            guard setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return }
            #endif
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            var request = Data()
            while !shouldStop, ProcessInfo.processInfo.systemUptime < deadline {
                var ready = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
                let count = poll(&ready, 1, 25)
                if count < 0 { if errno == EINTR { continue }; return }
                guard count > 0 else { continue }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let received = read(client, &bytes, bytes.count)
                if received < 0, errno == EAGAIN || errno == EINTR { continue }
                guard received > 0, received <= 65_536 - request.count else { return }
                request.append(contentsOf: bytes.prefix(received))
                guard let headerEnd = request.range(of: Data([13, 10, 13, 10])) else { continue }
                let header = String(decoding: request[..<headerEnd.lowerBound], as: UTF8.self)
                let lines = header.components(separatedBy: "\r\n")
                let length = lines.first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                guard length >= 0, length <= 65_536 - headerEnd.upperBound else { return }
                guard request.count >= headerEnd.upperBound + length else { continue }
                let redirected = lines.first?.split(separator: " ").dropFirst().first == "/destination"
                lock.withLock {
                    if redirected { destination = true }
                    else {
                        sourceReceivedPromptAndKey = header.contains("Bearer synthetic-key")
                            && String(decoding: request[headerEnd.upperBound...], as: UTF8.self).contains("Synthetic private prompt")
                    }
                }
                let response = redirected
                    ? "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    : "HTTP/1.1 307 Temporary Redirect\r\nLocation: http://127.0.0.1:\(port)/destination\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                send(Data(response.utf8), to: client, deadline: deadline)
                return
            }
        }

        private func send(_ data: Data, to client: Int32, deadline: TimeInterval) {
            data.withUnsafeBytes { bytes in
                var offset = 0
                while !shouldStop, offset < bytes.count, ProcessInfo.processInfo.systemUptime < deadline {
                    var ready = pollfd(fd: client, events: Int16(POLLOUT), revents: 0)
                    let count = poll(&ready, 1, 25)
                    if count < 0 { if errno == EINTR { continue }; return }
                    guard count > 0 else { continue }
                    #if canImport(Darwin)
                    let sent = Darwin.send(client, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                    #else
                    let sent = Glibc.send(client, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, Int32(MSG_NOSIGNAL))
                    #endif
                    if sent < 0, errno == EAGAIN || errno == EINTR { continue }
                    guard sent > 0 else { return }
                    offset += sent
                }
            }
        }
    }
}
