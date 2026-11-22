import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import ZeusCore

@Suite("Chrome bridge reply ownership", .serialized)
struct BridgePendingRepliesTests {
    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value
        init(_ value: Value) { self.value = value }
        func read() -> Value { lock.withLock { value } }
        func change(_ update: (inout Value) -> Void) { lock.withLock { update(&value) } }
    }

    private func eventually(_ condition: @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }

    @Test func duplicateProtocolRequestGetsItsOwnErrorWhileOriginalReplyAndBothSocketsComplete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-br-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("b.sock").path
        let pending = BridgePendingReplies()
        let forwarded = Box(0)
        let server = UnixSocketServer(path: path) { line, reply in
            guard let request = try? JSONDecoder().decode(BridgeRequest.self, from: line) else { reply(nil); return }
            if pending.reserve(id: request.id, reply: reply) != nil { forwarded.change { $0 += 1 } }
        }
        try server.start()
        defer { server.stop() }
        let request = try JSONEncoder().encode(BridgeRequest(id: "same-id", type: "page.read"))
        // The original stays open through the duplicate exchange. Three seconds is shorter than that
        // wait on a busy runner, so the client would drop the reply this test then completes.
        let original = Task.detached { UnixSocket.request(path: path, payload: request, expectReply: true, timeout: 20) }
        try await eventually { pending.count == 1 && forwarded.read() == 1 }
        let duplicateBytes = await Task.detached { UnixSocket.request(path: path, payload: request, expectReply: true, timeout: 3) }.value
        let duplicate = try JSONDecoder().decode(BridgeResponse.self, from: #require(duplicateBytes))
        #expect(duplicate.id == "same-id" && !duplicate.ok && duplicate.error?.code == "duplicate_request")
        #expect(pending.count == 1)
        #expect(forwarded.read() == 1, "Only the original request may be forwarded to Chrome")
        let success = BridgeResponse.success("same-id", .object(["original": .bool(true)]))
        #expect(pending.complete(success))
        let originalBytes = await original.value
        #expect(try JSONDecoder().decode(BridgeResponse.self, from: #require(originalBytes)) == success)
        #expect(!pending.complete(success))
        try await eventually { pending.count == 0 && server.activeConnectionCount == 0 }
    }

    @Test func anOldTimeoutCannotSettleAReusedRequestID() throws {
        let pending = BridgePendingReplies()
        let first = Box<[Data?]>([]), second = Box<[Data?]>([])
        let firstToken = try #require(pending.reserve(id: "reuse") { data in first.change { $0.append(data) } })
        let success = BridgeResponse.success("reuse", .string("done"))
        #expect(pending.complete(success))
        let secondToken = try #require(pending.reserve(id: "reuse") { data in second.change { $0.append(data) } })
        let timeout = BridgeResponse.failure("reuse", BridgeError(code: "timeout"))
        #expect(!pending.complete(timeout, token: firstToken))
        #expect(pending.count == 1 && second.read().isEmpty)
        #expect(pending.complete(timeout, token: secondToken))
        #expect(first.read().count == 1 && second.read().count == 1 && pending.count == 0)
        #expect(!pending.complete(timeout, token: secondToken))
    }

    @Test func simultaneousDuplicateReservationsHaveOneOwnerAndSettleEveryRejectedReply() async throws {
        let pending = BridgePendingReplies()
        let replies = Box<[Data?]>([])
        let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    pending.reserve(id: "racing") { data in replies.change { $0.append(data) } } != nil
                }
            }
            var count = 0
            for await reserved in group where reserved { count += 1 }
            return count
        }
        #expect(accepted == 1 && pending.count == 1 && replies.read().count == 31)
        #expect(pending.complete(.success("racing")))
        let decoded = try replies.read().map { try JSONDecoder().decode(BridgeResponse.self, from: #require($0)) }
        #expect(decoded.count == 32)
        #expect(decoded.filter(\.ok).count == 1)
        #expect(decoded.filter { $0.error?.code == "duplicate_request" }.count == 31)
        #expect(pending.count == 0)
    }

    @Test func terminalFailureDrainsAllRepliesOnceOutsideTheLockAndCancelsTheirTimers() async throws {
        let pending = BridgePendingReplies()
        let replies = Box<[Data?]>([])
        for id in ["first", "second"] {
            let token = try #require(pending.reserve(id: id) { data in
                #expect(pending.count == 0, "Terminal callbacks must run after the registry lock is released")
                replies.change { $0.append(data) }
            })
            #expect(pending.armTimeout(id: id, token: token, after: 10))
        }
        pending.failAll(BridgeError(code: "not_connected"))
        pending.failAll(BridgeError(code: "again"))
        try await Task.sleep(for: .milliseconds(80))
        #expect(replies.read().count == 2 && pending.count == 0)
        let responses = try replies.read().map { try JSONDecoder().decode(BridgeResponse.self, from: #require($0)) }
        #expect(responses.allSatisfy { $0.error?.code == "not_connected" })
        #expect(!pending.complete(.success("first")))
    }

    @Test func completedRequestTimerCanBeRearmedOnlyForTheCurrentReservation() async throws {
        let pending = BridgePendingReplies()
        let replies = Box<[Data?]>([])
        let first = try #require(pending.reserve(id: "reuse") { data in replies.change { $0.append(data) } })
        #expect(pending.armTimeout(id: "reuse", token: first, after: 10))
        #expect(pending.complete(.success("reuse"), token: first))
        let second = try #require(pending.reserve(id: "reuse") { data in replies.change { $0.append(data) } })
        #expect(pending.armTimeout(id: "reuse", token: second, after: 10))
        #expect(!pending.armTimeout(id: "reuse", token: first, after: 0.01))
        try await Task.sleep(for: .milliseconds(80))
        #expect(replies.read().count == 1 && pending.count == 1)
        #expect(pending.complete(.success("reuse"), token: second))
        #expect(replies.read().count == 2 && pending.count == 0)
    }

    @Test func aLiveReservationDeadlineProducesOneTimeoutReply() async throws {
        let pending = BridgePendingReplies()
        let replies = Box<[Data?]>([])
        let token = try #require(pending.reserve(id: "deadline") { data in replies.change { $0.append(data) } })
        #expect(pending.armTimeout(id: "deadline", token: token, after: 0.03))
        try await eventually { replies.read().count == 1 }
        let item = try #require(replies.read().first)
        let response = try JSONDecoder().decode(BridgeResponse.self, from: #require(item))
        #expect(response.error?.code == "timeout" && pending.count == 0)
        #expect(!pending.complete(.success("deadline"), token: token))
    }

    private func lifetimeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-life-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func reader() throws -> (Pipe, NativeMessageInput) {
        let pipe = Pipe()
        let input = try NativeMessageInput(handle: pipe.fileHandleForReading)
        return (pipe, input)
    }

    @Test func finishBeforeAttachLeavesAFileThisProcessDidNotBind() throws {
        let root = try lifetimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("chrome.sock")
        let marker = Data("keep-me".utf8)
        try marker.write(to: url)
        let lifetime = BridgeHostLifetime()
        lifetime.finish()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == marker)
    }

    @Test func finishAfterASuccessfulBindUnlinksTheSocket() throws {
        let root = try lifetimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("chrome.sock").path
        let (pipe, input) = try reader()
        defer { input.stop(); try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let server = UnixSocketServer(path: path) { _, _ in }
        try server.start()
        let lifetime = BridgeHostLifetime()
        lifetime.attach(input: input, server: server)
        lifetime.finish()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func finishLeavesAPathReplacedByAnotherInodeOrASymlink() throws {
        let root = try lifetimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("chrome.sock")
        let elsewhere = root.appendingPathComponent("other")
        try Data("target".utf8).write(to: elsewhere)
        let (pipe, input) = try reader()
        defer { input.stop(); try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let server = UnixSocketServer(path: url.path) { _, _ in }
        try server.start()
        let lifetime = BridgeHostLifetime()
        lifetime.attach(input: input, server: server)
        #expect(unlink(url.path) == 0)
        let replacement = Data("replaced".utf8)
        try replacement.write(to: url)
        lifetime.finish()
        #expect(try Data(contentsOf: url) == replacement)

        let second = root.appendingPathComponent("fresh.sock")
        let server2 = UnixSocketServer(path: second.path) { _, _ in }
        try server2.start()
        let lifetime2 = BridgeHostLifetime()
        lifetime2.attach(input: input, server: server2)
        #expect(unlink(second.path) == 0)
        #expect(symlink(elsewhere.path, second.path) == 0)
        lifetime2.finish()
        var info = stat()
        #expect(lstat(second.path, &info) == 0)
        #expect((info.st_mode & S_IFMT) == S_IFLNK)
    }

    @Test func finishLeavesAReplacementSocket() throws {
        let root = try lifetimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("chrome.sock")
        let (pipe, input) = try reader()
        defer { input.stop(); try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let server = UnixSocketServer(path: url.path) { _, _ in }
        try server.start()
        let lifetime = BridgeHostLifetime()
        lifetime.attach(input: input, server: server)
        #expect(unlink(url.path) == 0)
        let replacement = try Self.bindSocket(at: url.path)
        defer { close(replacement.fd) }
        var before = stat()
        #expect(lstat(url.path, &before) == 0)
        lifetime.finish()
        var after = stat()
        #expect(lstat(url.path, &after) == 0)
        #expect((after.st_mode & S_IFMT) == S_IFSOCK)
        #expect(after.st_ino == before.st_ino && after.st_dev == before.st_dev)
    }

    @Test func failedListenAfterBindLeavesAReplacementSocket() throws {
        let root = try lifetimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("listen.sock")
        let held = Box<Int32>(-1)
        let keptInode = Box<UInt64>(0)
        defer { let fd = held.read(); if fd >= 0 { close(fd) } }
        UnixSocketServer.rejectListenLock.lock()
        UnixSocketServer.rejectListenAfterBind = { path in
            _ = unlink(path)
            let bound = try? BridgePendingRepliesTests.bindSocket(at: path)
            if let bound {
                held.change { $0 = bound.fd }
                var info = stat()
                if lstat(path, &info) == 0 { keptInode.change { $0 = UInt64(info.st_ino) } }
            }
            return false
        }
        UnixSocketServer.rejectListenLock.unlock()
        defer {
            UnixSocketServer.rejectListenLock.lock()
            UnixSocketServer.rejectListenAfterBind = nil
            UnixSocketServer.rejectListenLock.unlock()
        }
        let server = UnixSocketServer(path: url.path) { _, _ in }
        #expect(throws: POSIXError.self) { try server.start() }
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        #expect((info.st_mode & S_IFMT) == S_IFSOCK)
        #expect(UInt64(info.st_ino) == keptInode.read() && keptInode.read() != 0)
    }

    private struct BoundFD {
        var fd: Int32
        var inode: UInt64
    }

    private static func bindSocket(at path: String) throws -> BoundFD {
        let fd = UnixSocket.makeSocket()
        try #require(fd >= 0)
        var address = try #require(UnixSocket.address(for: path))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { close(fd); throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { close(fd); throw POSIXError(.EIO) }
        return BoundFD(fd: fd, inode: UInt64(info.st_ino))
    }

    @Test func identityIsCapturedImmediatelyAfterStdinIsArmed() {
        #expect(BridgeHostStartup.identityIsCapturedImmediatelyAfterStdin())
    }

    @Test func driveRunsTheSharedStartupListInOrder() {
        var seen: [BridgeHostStartup.Step] = []
        BridgeHostStartup.drive { seen.append($0) }
        #expect(seen == [.bindSocket, .armStdin, .captureIdentity, .markIdentityReady])
        #expect(seen == BridgeHostStartup.steps)
    }

    @Test func theHostDrivesThatListAndNoOtherOrder() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent("Sources/zeus-bridge/main.swift"), encoding: .utf8)
        let drive = try #require(source.range(of: "BridgeHostStartup.drive {"))
        #expect(source.range(of: "for step in") == nil)
        let bind = try #require(source.range(of: "server.start()"))
        let arm = try #require(source.range(of: "input.start("))
        let capture = try #require(source.range(of: "PeerSigning.captureOwnIdentity()"))
        let ready = try #require(source.range(of: "relay.noteIdentityReady()"))
        #expect(drive.lowerBound < bind.lowerBound)
        #expect(drive.lowerBound < arm.lowerBound)
        #expect(drive.lowerBound < capture.lowerBound)
        #expect(drive.lowerBound < ready.lowerBound)
        #expect(source.components(separatedBy: "PeerSigning.captureOwnIdentity()").count == 2)
        #expect(source.components(separatedBy: "input.start(").count == 2)
        #expect(source.components(separatedBy: "server.start()").count == 2)
        #expect(source.components(separatedBy: "relay.noteIdentityReady()").count == 2)
    }

    @Test func finishLeavesASocketWithTheSameInodeOnAnotherDevice() throws {
        let root = try lifetimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("chrome.sock").path
        let server = UnixSocketServer(path: path) { _, _ in }
        try server.start()
        defer { server.stop(); clearUnlinkProbe() }
        var info = stat()
        #expect(lstat(path, &info) == 0)
        let inode = UInt64(info.st_ino)
        let device = UInt64(info.st_dev)
        UnixSocketServer.unlinkProbeLock.lock()
        UnixSocketServer.unlinkProbe = { _ in
            UnixSocketServer.DirectoryEntry(device: device &+ 1, inode: inode, kind: .socket)
        }
        UnixSocketServer.unlinkProbeLock.unlock()
        server.stop()
        var after = stat()
        #expect(lstat(path, &after) == 0)
        #expect((after.st_mode & S_IFMT) == S_IFSOCK)
        #expect(UInt64(after.st_ino) == inode && UInt64(after.st_dev) == device)
    }

    @Test func finishKeepsASymlinkToARegularFileByLstat() throws {
        let root = try lifetimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("chrome.sock")
        let file = root.appendingPathComponent("notes.txt")
        let text = Data("keep-the-file".utf8)
        try text.write(to: file)
        let server = UnixSocketServer(path: url.path) { _, _ in }
        try server.start()
        defer { server.stop(); clearUnlinkProbe() }
        clearUnlinkProbe()
        #expect(unlink(url.path) == 0)
        #expect(symlink(file.path, url.path) == 0)
        server.stop()
        var link = stat()
        #expect(lstat(url.path, &link) == 0)
        #expect((link.st_mode & S_IFMT) == S_IFLNK)
        #expect(try Data(contentsOf: file) == text)
        var target = stat()
        #expect(stat(file.path, &target) == 0)
        let probe = try #require(UnixSocketServer.unlinkProbeLock.withLock { UnixSocketServer.lastUnlinkProbe })
        #expect(probe.kind == .symlink)
        #expect(probe.inode == UInt64(link.st_ino))
        #expect(probe.inode != UInt64(target.st_ino))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func clearUnlinkProbe() {
        UnixSocketServer.unlinkProbeLock.lock()
        UnixSocketServer.unlinkProbe = nil
        UnixSocketServer.lastUnlinkProbe = nil
        UnixSocketServer.unlinkProbeLock.unlock()
    }

    @Test func socketIsBoundBeforeStdinAndIdentityFollowsTheReader() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/zeus-bridge/main.swift"), encoding: .utf8)
        let bound = try #require(source.range(of: "try? server.start()"))
        let reading = try #require(source.range(of: "input.start("))
        let identity = try #require(source.range(of: "PeerSigning.captureOwnIdentity()"))
        let ready = try #require(source.range(of: "relay.noteIdentityReady()"))
        #expect(bound.lowerBound < reading.lowerBound)
        #expect(reading.lowerBound < identity.lowerBound)
        #expect(identity.lowerBound < ready.lowerBound)
    }

    @Test func aPeerIsRefusedBeforeOwnIdentityIsCaptured() async throws {
        let root = try lifetimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("peer.sock").path
        let saw = Box(0)
        let ownName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        let server = UnixSocketServer(path: path, peerPolicy: .sameUserExecutable([ownName]), peerVerifier: { _ in
            .deny("own code signature unavailable")
        }) { _, reply in
            saw.change { $0 += 1 }
            reply(Data("open".utf8))
        }
        try server.start()
        defer { server.stop() }
        let fd = UnixSocket.makeSocket()
        try #require(fd >= 0)
        defer { close(fd) }
        var address = try #require(UnixSocket.address(for: path))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        try #require(connected == 0)
        try #require(UnixSocket.prepare(fd))
        _ = UnixSocket.writeAll(fd, Data("{\"id\":\"p\",\"type\":\"ping\"}\n".utf8))
        let reply = await Task.detached { UnixSocket.readLine(fd, timeout: 1) }.value
        #expect(reply == nil)
        #expect(saw.read() == 0)
    }

    @Test func beforeOwnIdentityOnlyPingAndUnknownTypeAreAnswered() throws {
        let ping = try JSONEncoder().encode(BridgeRequest(id: "p", type: "ping"))
        guard case .reply(let pong) = BridgeChromeAdmission.action(for: ping, identityReady: false) else {
            Issue.record("ping was not answered")
            return
        }
        #expect(pong.ok && pong.result?["pong"]?.boolValue == true)

        let read = try JSONEncoder().encode(BridgeRequest(id: "r", type: "page.read"))
        guard case .reply(let refused) = BridgeChromeAdmission.action(for: read, identityReady: false) else {
            Issue.record("page.read was not answered with a refusal")
            return
        }
        #expect(!refused.ok && refused.error?.code == "unknown_type")

        let done = try JSONEncoder().encode(BridgeResponse.success("pending-id", .bool(true)))
        let early = BridgeChromeAdmission.action(for: done, identityReady: false)
        if case .completePending = early {
            Issue.record("a Chrome response settled a pending reply before identity was captured")
        }
        guard case .reply(let blocked) = early else {
            Issue.record("a Chrome response before identity was not refused")
            return
        }
        #expect(!blocked.ok && blocked.error?.code == "unknown_type")
    }

}
