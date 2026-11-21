import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import ZeusCore

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
        func waitForSocket() {
            let found = OwnedBridgeWait.until(seconds: 2) {
                FileManager.default.fileExists(atPath: self.path) || !self.process.isRunning
            }
            #expect(found && FileManager.default.fileExists(atPath: path))
        }
        func waitForExit(seconds: Double) -> Bool {
            _ = OwnedBridgeWait.until(seconds: seconds) { !self.process.isRunning }
            return !process.isRunning
        }
        func readAllOutput(seconds: Double) -> Data? {
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
                if count < 0 { usleep(5_000) }
            }
            Issue.record("Owned native-host output did not reach EOF before the deadline")
            return nil
        }

        func waitForForwardedBytes() -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while process.isRunning && ContinuousClock.now < deadline {
                var ready = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                if poll(&ready, 1, 0) > 0, ready.revents & Int16(POLLIN) != 0 { return true }
                usleep(5_000)
            }
            return false
        }
    }

    @Test func oversizedHeaderIsRejectedBeforeBodyAndPendingSocketIsSettled() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.waitForSocket()
        let request = try JSONEncoder().encode(BridgeRequest(id: "pending-before-invalid-header", type: "fixture.no-browser"))
        let reply = OwnedBridgeWait.start { UnixSocket.request(path: fixture.path, payload: request, expectReply: true, timeout: 4) }
        #expect(fixture.waitForForwardedBytes())
        // The entire malformed input is four bytes, not a multi-gigabyte allocation.
        try fixture.input.fileHandleForWriting.write(contentsOf: Data([0xff, 0xff, 0xff, 0xff]))
        let exited = fixture.waitForExit(seconds: 2)
        #expect(exited)
        guard exited else { fixture.stop(); _ = reply.wait(); return }
        let result = reply.wait()
        if let result {
            let response = try JSONDecoder().decode(BridgeResponse.self, from: result)
            #expect(!response.ok && response.error?.code == BridgeError.notConnected)
        }
        #expect(fixture.process.terminationReason == .exit && fixture.process.terminationStatus == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.path))
    }

    @Test func nonReadingChromeCannotStrandPendingRequestsOrKeepOpenStdinAlive() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.waitForSocket()
        let large = try JSONEncoder().encode(BridgeRequest(id: "blocked-output", type: "fixture.no-browser",
            params: ["synthetic": .string(String(repeating: "x", count: 512 * 1024))]))
        let first = OwnedBridgeWait.start { UnixSocket.request(path: fixture.path, payload: large, expectReply: true, timeout: 5) }
        #expect(fixture.waitForForwardedBytes())
        let secondRequest = try JSONEncoder().encode(BridgeRequest(id: "queued-output", type: "fixture.no-browser"))
        let second = OwnedBridgeWait.start { UnixSocket.request(path: fixture.path, payload: secondRequest, expectReply: true, timeout: 5) }
        // Stdout is deliberately unread and stdin deliberately remains open throughout this wait.
        let exited = fixture.waitForExit(seconds: 3.5)
        #expect(exited)
        guard exited else { fixture.stop(); _ = first.wait(); _ = second.wait(); return }
        for result in [first.wait(), second.wait()] {
            if let result {
                let response = try JSONDecoder().decode(BridgeResponse.self, from: result)
                #expect(!response.ok && response.error?.code == BridgeError.notConnected)
            }
        }
        #expect(fixture.process.terminationReason == .exit && fixture.process.terminationStatus == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.path))
    }

    @Test func cleanEOFFlushesAnAlreadyAcceptedCompleteResponseBeforeExit() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.waitForSocket()
        let type = String(repeating: "unknown-", count: 20_000)
        let request = try JSONEncoder().encode(BridgeRequest(id: "reply-before-clean-eof", type: type))
        try fixture.input.fileHandleForWriting.write(contentsOf: NativeMessagingFrame.encode(request))
        try fixture.input.fileHandleForWriting.close()
        // The response exceeds pipe capacity. Let EOF race with its blocked write before draining.
        usleep(50_000)
        let bytes = try #require(fixture.readAllOutput(seconds: 3))
        var decoder = NativeMessagingFrame.Decoder()
        var replies: [Data] = []
        try decoder.consume(bytes) { replies.append($0) }
        try decoder.finish()
        #expect(replies.count == 1)
        let reply = try JSONDecoder().decode(BridgeResponse.self, from: #require(replies.first))
        #expect(reply.id == "reply-before-clean-eof" && reply.error?.code == "unknown_type" && reply.error?.message == type)
        let exited = fixture.waitForExit(seconds: 2)
        #expect(exited)
        guard exited else { return }
        #expect(fixture.process.terminationReason == .exit && fixture.process.terminationStatus == 0)
    }

    @Test func cleanEOFAndTruncatedFrameEOFHaveDistinctExitOutcomes() throws {
        for partial in [false, true] {
            let fixture = try Fixture()
            defer { fixture.stop() }
            fixture.waitForSocket()
            if partial { try fixture.input.fileHandleForWriting.write(contentsOf: Data([1, 0])) }
            try fixture.input.fileHandleForWriting.close()
            let exited = fixture.waitForExit(seconds: 2)
            #expect(exited)
            guard exited else { continue }
            #expect(fixture.process.terminationReason == .exit)
            #expect(fixture.process.terminationStatus == (partial ? 2 : 0))
            #expect(!FileManager.default.fileExists(atPath: fixture.path))
        }
    }
}
