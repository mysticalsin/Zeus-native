import Foundation
import Testing
@testable import ZeusCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Disposable AF_UNIX peers only. No app, network service, permissions, capture or user files.
@Suite("Bounded local socket transport", .serialized)
struct UnixSocketSafetyTests {
    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value
        init(_ value: Value) { self.value = value }
        func read() -> Value { lock.withLock { value } }
        func set(_ value: Value) { lock.withLock { self.value = value } }
        func change(_ body: (inout Value) -> Void) { lock.withLock { body(&value) } }
    }

    private func location() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-ipc-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func connectClient(_ path: String) throws -> Int32 {
        let fd = UnixSocket.makeSocket()
        try #require(fd >= 0)
        do {
            var address = try #require(UnixSocket.address(for: path))
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            try #require(result == 0)
            try #require(UnixSocket.prepare(fd))
            return fd
        } catch { close(fd); throw error }
    }

    private func eventually(_ condition: @Sendable () -> Bool, seconds: Double = 3) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    @MainActor @Test func nonReadingPeerDoesNotBlockMainActorAndReplyTimesOut() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let replyDuration = Box<Duration?>(nil)
        let heartbeat = Box(false)
        let largeReply = Data(repeating: 0x78, count: UnixSocket.maximumMessageBytes)
        let server = UnixSocketServer(path: root.appendingPathComponent("s.sock").path) { _, reply in
            Task { @MainActor in
                let began = ContinuousClock.now
                reply(largeReply)
                replyDuration.set(began.duration(to: .now))
                Task { @MainActor in heartbeat.set(true) }
            }
        }
        try server.start()
        defer { server.stop() }
        let client = try connectClient(root.appendingPathComponent("s.sock").path)
        defer { close(client) }
        var smallBuffer: Int32 = 1024
        _ = setsockopt(client, SOL_SOCKET, SO_RCVBUF, &smallBuffer, socklen_t(MemoryLayout<Int32>.size))
        // A detached watchdog releases a broken synchronous writer, so this regression fails
        // an assertion instead of leaving the test process's main actor stuck forever.
        let watchdog = Task.detached {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            _ = shutdown(client, Int32(SHUT_RDWR))
        }
        #expect(UnixSocket.writeAll(client, Data("hi\n".utf8)))
        try await eventually { replyDuration.read() != nil && heartbeat.read() }
        watchdog.cancel()
        await watchdog.value
        let duration = try #require(replyDuration.read())
        #expect(duration < .milliseconds(250), "A non-reading peer blocked MainActor inside reply()")
        try await eventually({ server.activeConnectionCount == 0 }, seconds: 2)
        // The peer remained open and never consumed the response; only the send deadline closes it.
        #expect(heartbeat.read())
    }

    @Test func duplicateAndLateRepliesCannotWriteOrCloseTwice() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let retained = Box<UnixSocketServer.Reply?>(nil)
        let server = UnixSocketServer(path: root.appendingPathComponent("s.sock").path) { _, reply in
            retained.set(reply)
            reply(Data("first".utf8))
            reply(Data("second".utf8))
        }
        try server.start()
        defer { server.stop() }
        let client = try connectClient(root.appendingPathComponent("s.sock").path)
        defer { close(client) }
        #expect(UnixSocket.writeAll(client, Data("hi\n".utf8)))
        let response = await Task.detached { UnixSocket.readLine(client, timeout: 2) }.value
        #expect(response == Data("first".utf8))
        try await eventually { server.activeConnectionCount == 0 }
        let late = try #require(retained.read())
        late(Data("late".utf8))
        late(nil)
        #expect(await Task.detached { UnixSocket.readLine(client, timeout: 0.2) }.value == nil)
        #expect(server.activeConnectionCount == 0)
    }

    @Test func oversizedIdentifiersAndLinesNeverReachHandler() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let handled = Box(0)
        let server = UnixSocketServer(path: root.appendingPathComponent("s.sock").path) { _, reply in
            handled.change { $0 += 1 }; reply(Data("unexpected".utf8))
        }
        try server.start()
        defer { server.stop() }
        let id = String(repeating: "a", count: UnixSocket.maximumIdentifierBytes + 1)
        let invalidID = try JSONSerialization.data(withJSONObject: ["id": id, "kind": "zeus.command", "op": "status"])
        for payload in [invalidID + Data([0x0A]), Data(repeating: 0x78, count: UnixSocket.maximumMessageBytes + 1)] {
            let client = try connectClient(root.appendingPathComponent("s.sock").path)
            _ = await Task.detached { UnixSocket.writeAll(client, payload) }.value
            #expect(await Task.detached { UnixSocket.readLine(client, timeout: 2) }.value == nil)
            close(client)
        }
        try await eventually { server.activeConnectionCount == 0 }
        #expect(handled.read() == 0)
    }

    @Test func oversizedResponseAndIdentifierAreNotPublished() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let large = Data(repeating: 0x78, count: UnixSocket.maximumMessageBytes + 1)
        let id = try JSONSerialization.data(withJSONObject: ["id": String(repeating: "b", count: 257), "ok": true])
        for payload in [large, id] {
            let path = root.appendingPathComponent("s.sock").path
            let server = UnixSocketServer(path: path) { _, reply in reply(payload) }
            try server.start()
            let response = await Task.detached { UnixSocket.request(path: path, payload: Data("hi".utf8), expectReply: true, timeout: 2) }.value
            #expect(response == nil)
            try await eventually { server.activeConnectionCount == 0 }
            server.stop()
        }
    }

    @Test func pendingHandlerKeepsItsReplyBeyondTheReadDeadline() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("s.sock").path
        let server = UnixSocketServer(path: path) { _, reply in
            DispatchQueue.global().asyncAfter(deadline: .now() + UnixSocket.requestReadTimeout + 0.1) { reply(Data("approved".utf8)) }
        }
        try server.start()
        defer { server.stop() }
        let response = await Task.detached { UnixSocket.request(path: path, payload: Data("waiting".utf8), expectReply: true, timeout: 4) }.value
        #expect(response == Data("approved".utf8))
        try await eventually { server.activeConnectionCount == 0 }
    }

    @Test func connectionLimitAndStopCloseEveryWaitingPeer() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let replies = Box<[UnixSocketServer.Reply]>([])
        let path = root.appendingPathComponent("s.sock").path
        let server = UnixSocketServer(path: path) { _, reply in replies.change { $0.append(reply) } }
        try server.start()
        defer { server.stop() }
        var peers: [Int32] = []
        defer { peers.forEach { close($0) } }
        for count in 1...UnixSocketServer.maximumConnections {
            let peer = try connectClient(path)
            peers.append(peer)
            #expect(UnixSocket.writeAll(peer, Data("hold\n".utf8)))
            try await eventually { replies.read().count == count }
        }
        let rejected = try connectClient(path)
        peers.append(rejected)
        #expect(await Task.detached { UnixSocket.readLine(rejected, timeout: 1) }.value == nil)
        #expect(server.activeConnectionCount == UnixSocketServer.maximumConnections)
        #expect(replies.read().count == UnixSocketServer.maximumConnections)
        server.stop()
        try await eventually { server.activeConnectionCount == 0 }
        for reply in replies.read() { reply(Data("after-stop".utf8)) }
        for peer in peers { #expect(UnixSocket.readLine(peer, timeout: 0.1) == nil) }
    }

    @Test func partialTimeoutDoesNotDispatchButCleanEOFDoes() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let seen = Box<[Data]>([])
        let path = root.appendingPathComponent("s.sock").path
        let server = UnixSocketServer(path: path) { line, reply in seen.change { $0.append(line) }; reply(line) }
        try server.start()
        defer { server.stop() }
        let partial = try connectClient(path)
        #expect(UnixSocket.writeAll(partial, Data("valid-prefix".utf8)))
        #expect(await Task.detached { UnixSocket.readLine(partial, timeout: 3) }.value == nil)
        close(partial)
        #expect(seen.read().isEmpty)
        let complete = try connectClient(path)
        defer { close(complete) }
        #expect(UnixSocket.writeAll(complete, Data("complete".utf8)))
        _ = shutdown(complete, Int32(SHUT_WR))
        #expect(await Task.detached { UnixSocket.readLine(complete, timeout: 2) }.value == Data("complete".utf8))
        #expect(seen.read() == [Data("complete".utf8)])
    }

    @Test func droppingServerClosesPendingPeerAndRejectsRetainedReply() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let retained = Box<UnixSocketServer.Reply?>(nil)
        let path = root.appendingPathComponent("s.sock").path
        var server: UnixSocketServer? = UnixSocketServer(path: path) { _, reply in retained.set(reply) }
        weak var weakServer = server
        try server?.start()
        let client = try connectClient(path)
        defer { close(client) }
        #expect(UnixSocket.writeAll(client, Data("hold\n".utf8)))
        try await eventually { retained.read() != nil }
        server = nil
        #expect(weakServer == nil)
        #expect(await Task.detached { UnixSocket.readLine(client, timeout: 1) }.value == nil)
        retained.read()?(Data("too-late".utf8))
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func disconnectedPeerCannotSignalTheProcessDuringReply() async throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let retained = Box<UnixSocketServer.Reply?>(nil)
        let path = root.appendingPathComponent("s.sock").path
        let server = UnixSocketServer(path: path) { _, reply in retained.set(reply) }
        try server.start()
        defer { server.stop() }
        let client = try connectClient(path)
        #expect(UnixSocket.writeAll(client, Data("hold\n".utf8)))
        try await eventually { retained.read() != nil }
        _ = shutdown(client, Int32(SHUT_RDWR))
        close(client)
        retained.read()?(Data(repeating: 0x78, count: UnixSocket.maximumMessageBytes))
        try await eventually { server.activeConnectionCount == 0 }
    }

    @Test func serverDoesNotRemoveRegularFilesOrSymlinks() throws {
        let root = try location()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: original)
        let link = root.appendingPathComponent("link.sock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        for path in [original.path, link.path] {
            let server = UnixSocketServer(path: path) { _, reply in reply(nil) }
            #expect(throws: POSIXError.self) { try server.start() }
            server.stop()
        }
        #expect(try Data(contentsOf: original) == Data("keep".utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == original.path)
        #expect(UnixSocket.address(for: "/tmp/hidden\0tail") == nil)
    }
}
