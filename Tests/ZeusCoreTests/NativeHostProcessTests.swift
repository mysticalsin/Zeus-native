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
            let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let executable = package.appendingPathComponent(".build/debug/zeus-bridge")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
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

        func stop() {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
            try? FileManager.default.removeItem(at: root)
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

    @Test func oversizedHeaderIsRejectedBeforeBodyAndPendingSocketIsSettled() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        try await fixture.waitForSocket()
        let request = try JSONEncoder().encode(BridgeRequest(id: "pending-before-invalid-header", type: "fixture.no-browser"))
        let reply = Task.detached { UnixSocket.request(path: fixture.path, payload: request, expectReply: true, timeout: 4) }
        #expect(try await fixture.waitForForwardedBytes())
        // The entire malformed input is four bytes, not a multi-gigabyte allocation.
        try fixture.input.fileHandleForWriting.write(contentsOf: Data([0xff, 0xff, 0xff, 0xff]))
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
        try fixture.input.fileHandleForWriting.write(contentsOf: NativeMessagingFrame.encode(request))
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
            if partial { try fixture.input.fileHandleForWriting.write(contentsOf: Data([1, 0])) }
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
