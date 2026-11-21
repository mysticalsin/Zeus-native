import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import ZeusCore

private final class PipeWriteFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int?
    func store(_ count: Int) { lock.withLock { stored = count } }
    var isReady: Bool { lock.withLock { stored != nil } }
    var value: Int { lock.withLock { stored ?? -1 } }
}

/// A pipe write that returns when the buffer is full. `FileHandle.write` waits until a reader
/// drains it, which freezes the host fixture when `zeus-bridge` has not armed stdin yet.
private enum BoundedFileWrite {
    static func write(_ handle: FileHandle, _ data: Data, timeout: TimeInterval) throws -> Int {
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw POSIXError(.EIO) }
        defer { _ = fcntl(fd, F_SETFL, flags) }
        #if canImport(Darwin)
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        #else
        var mask = sigset_t(), previous = sigset_t(), pending = sigset_t()
        sigemptyset(&mask); sigaddset(&mask, SIGPIPE)
        let masked = pthread_sigmask(SIG_BLOCK, &mask, &previous) == 0
        sigpending(&pending)
        let alreadyPending = sigismember(&pending, SIGPIPE) == 1
        defer {
            if masked {
                if !alreadyPending {
                    sigpending(&pending)
                    if sigismember(&pending, SIGPIPE) == 1 {
                        var zero = timespec(tv_sec: 0, tv_nsec: 0)
                        _ = sigtimedwait(&mask, nil, &zero)
                    }
                }
                pthread_sigmask(SIG_SETMASK, &previous, nil)
            }
        }
        #endif
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        var offset = 0
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while offset < raw.count {
                if ContinuousClock.now >= deadline { return }
                var slot = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let ready = poll(&slot, 1, 20)
                if ready < 0 { if errno == EINTR { continue }; throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                if ready == 0 { continue }
                if slot.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { throw POSIXError(.EPIPE) }
                let count: Int
                #if canImport(Darwin)
                count = Darwin.write(fd, base.advanced(by: offset), min(16_384, raw.count - offset))
                #else
                count = Glibc.write(fd, base.advanced(by: offset), min(16_384, raw.count - offset))
                #endif
                if count > 0 { offset += count; continue }
                if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                if count < 0 && errno == EPIPE { throw POSIXError(.EPIPE) }
                throw POSIXError(.EIO)
            }
        }
        return offset
    }
}

/// Exact built native-host process, synthetic frames and an isolated support directory only.
/// Does not register/open Chrome, invoke a browser action, or inspect user settings or credentials.
@Suite("Native host process boundaries", .serialized)
struct NativeHostProcessTests {
    private final class Fixture: @unchecked Sendable {
        let root: URL
        let process = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        var path: String { root.appendingPathComponent("chrome.sock").path }

        init() throws {
            // The helper is built beside the test bundle, wherever the scratch path points. The default package
            // `.build` folder is only the fallback for a plain `swift test` run.
            let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let products = Bundle(for: Fixture.self).bundleURL.deletingLastPathComponent()
            let candidates = [products.appendingPathComponent("zeus-bridge"),
                              package.appendingPathComponent(".build/debug/zeus-bridge")]
            guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-nh-\(UUID().uuidString.prefix(8))")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            process.executableURL = executable
            process.environment = ["ZEUS_SUPPORT_DIR": root.path]
            process.standardInput = input; process.standardOutput = output; process.standardError = errors
            do { try process.run() }
            catch { try? FileManager.default.removeItem(at: root); throw error }
        }

        /// Bounded on purpose. `waitUntilExit` runs a nested run loop, and on a Swift concurrency thread of a busy
        /// machine it can wait forever for a helper that is already gone (seen as a 30 minute gate timeout).
        func stop() {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while process.isRunning, ContinuousClock.now < deadline { usleep(5_000) }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
            try? FileManager.default.removeItem(at: root)
        }
        /// Chrome frames are larger than the pipe. A host that is not reading must make this return,
        /// not leave the caller blocked in `FileHandle.write`.
        @discardableResult
        func send(_ data: Data, timeout: TimeInterval = 2) throws -> Int {
            try BoundedFileWrite.write(input.fileHandleForWriting, data, timeout: timeout)
        }

        func waitForSocket() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !FileManager.default.fileExists(atPath: path), process.isRunning, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(FileManager.default.fileExists(atPath: path))
        }
        func waitForExit(seconds: Double) async throws -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
            while process.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
            return !process.isRunning
        }
        func readAllOutput(seconds: Double) async throws -> Data? {
            let fd = output.fileHandleForReading.fileDescriptor
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
                Issue.record("Could not make the owned fixture reader nonblocking"); return nil
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
            var result = Data(), bytes = [UInt8](repeating: 0, count: 16_384)
            while ContinuousClock.now < deadline {
                #if canImport(Darwin)
                let count = Darwin.read(fd, &bytes, bytes.count)
                #else
                let count = Glibc.read(fd, &bytes, bytes.count)
                #endif
                if count == 0 { return result }
                if count > 0 {
                    guard result.count + count <= NativeMessagingFrame.maxHostToChromeBytes + 4 else {
                        Issue.record("Fixture received more than one bounded response"); return nil
                    }
                    result.append(contentsOf: bytes.prefix(count))
                } else if errno != EINTR && errno != EAGAIN {
                    Issue.record("Owned fixture output failed"); return nil
                }
                if count < 0 { try await Task.sleep(for: .milliseconds(5)) }
            }
            Issue.record("Owned native-host output did not reach EOF before the deadline")
            return nil
        }

        func waitForForwardedBytes() async throws -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            repeat {
                var ready = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                if poll(&ready, 1, 0) > 0, ready.revents & Int16(POLLIN) != 0 { return true }
                try await Task.sleep(for: .milliseconds(5))
            } while process.isRunning && ContinuousClock.now < deadline
            return false
        }
    }

    /// Chrome's framed stdin is larger than a pipe. The write has to return while the read end is
    /// still open and idle. A blocking write is closed at 2 seconds so the suite fails instead of hanging.
    @Test func unreadStdinPipeWriteReturnsBeforeTheReaderDrains() async throws {
        let pipe = Pipe()
        let payload = Data(repeating: 0x61, count: 512 * 1024)
        let wrote = PipeWriteFlag()
        let worker = Task.detached {
            let count = try? BoundedFileWrite.write(pipe.fileHandleForWriting, payload, timeout: 0.4)
            if let count { wrote.store(count) }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !wrote.isReady, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if !wrote.isReady {
            try? pipe.fileHandleForReading.close()
            _ = await worker.value
            Issue.record("stdin write did not return before the 2 second test deadline")
            try? pipe.fileHandleForWriting.close()
            return
        }
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
        _ = await worker.value
        #expect(wrote.value < payload.count)
    }

    @Test func oversizedHeaderIsRejectedBeforeBodyAndPendingSocketIsSettled() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        try await fixture.waitForSocket()
        let request = try JSONEncoder().encode(BridgeRequest(id: "pending-before-invalid-header", type: "fixture.no-browser"))
        let reply = Task.detached { UnixSocket.request(path: fixture.path, payload: request, expectReply: true, timeout: 4) }
        #expect(try await fixture.waitForForwardedBytes())
        // The entire malformed input is four bytes, not a multi-gigabyte allocation.
        #expect(try fixture.send(Data([0xff, 0xff, 0xff, 0xff])) == 4)
        let exited = try await fixture.waitForExit(seconds: 2)
        #expect(exited)
        guard exited else { fixture.stop(); _ = await reply.value; return }
        let result = await reply.value
        if let result {
            let response = try JSONDecoder().decode(BridgeResponse.self, from: result)
            #expect(!response.ok && response.error?.code == BridgeError.notConnected)
        }
        #expect(fixture.process.terminationReason == .exit && fixture.process.terminationStatus == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.path))
    }

    @Test func nonReadingChromeCannotStrandPendingRequestsOrKeepOpenStdinAlive() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        try await fixture.waitForSocket()
        let large = try JSONEncoder().encode(BridgeRequest(id: "blocked-output", type: "fixture.no-browser",
            params: ["synthetic": .string(String(repeating: "x", count: 512 * 1024))]))
        let first = Task.detached { UnixSocket.request(path: fixture.path, payload: large, expectReply: true, timeout: 5) }
        #expect(try await fixture.waitForForwardedBytes())
        let secondRequest = try JSONEncoder().encode(BridgeRequest(id: "queued-output", type: "fixture.no-browser"))
        let second = Task.detached { UnixSocket.request(path: fixture.path, payload: secondRequest, expectReply: true, timeout: 5) }
        // Stdout is deliberately unread and stdin deliberately remains open throughout this wait.
        let exited = try await fixture.waitForExit(seconds: 3.5)
        #expect(exited)
        guard exited else { fixture.stop(); _ = await first.value; _ = await second.value; return }
        for result in [await first.value, await second.value] {
            if let result {
                let response = try JSONDecoder().decode(BridgeResponse.self, from: result)
                #expect(!response.ok && response.error?.code == BridgeError.notConnected)
            }
        }
        #expect(fixture.process.terminationReason == .exit && fixture.process.terminationStatus == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.path))
    }

    @Test func cleanEOFFlushesAnAlreadyAcceptedCompleteResponseBeforeExit() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        try await fixture.waitForSocket()
        let type = String(repeating: "unknown-", count: 20_000)
        let request = try JSONEncoder().encode(BridgeRequest(id: "reply-before-clean-eof", type: type))
        let frame = try NativeMessagingFrame.encode(request)
        #expect(try fixture.send(frame) == frame.count)
        try fixture.input.fileHandleForWriting.close()
        // The response exceeds pipe capacity. Let EOF race with its blocked write before draining.
        try await Task.sleep(for: .milliseconds(50))
        let bytes = try #require(await fixture.readAllOutput(seconds: 3))
        var decoder = NativeMessagingFrame.Decoder()
        var replies: [Data] = []
        try decoder.consume(bytes) { replies.append($0) }
        try decoder.finish()
        #expect(replies.count == 1)
        let reply = try JSONDecoder().decode(BridgeResponse.self, from: #require(replies.first))
        #expect(reply.id == "reply-before-clean-eof" && reply.error?.code == "unknown_type" && reply.error?.message == type)
        let exited = try await fixture.waitForExit(seconds: 2)
        #expect(exited)
        guard exited else { return }
        #expect(fixture.process.terminationReason == .exit && fixture.process.terminationStatus == 0)
    }

    @Test func cleanEOFAndTruncatedFrameEOFHaveDistinctExitOutcomes() async throws {
        for partial in [false, true] {
            let fixture = try Fixture()
            defer { fixture.stop() }
            try await fixture.waitForSocket()
            if partial { #expect(try fixture.send(Data([1, 0])) == 2) }
            try fixture.input.fileHandleForWriting.close()
            let exited = try await fixture.waitForExit(seconds: 2)
            #expect(exited)
            guard exited else { continue }
            #expect(fixture.process.terminationReason == .exit)
            #expect(fixture.process.terminationStatus == (partial ? 2 : 0))
            #expect(!FileManager.default.fileExists(atPath: fixture.path))
        }
    }
}
