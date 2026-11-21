import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import ZeusCore

/// Waits that keep the calling thread. An async sleep lets its deadline run while the cooperative
/// pool is busy, so these helpers block here and run socket calls on a dispatch thread.
enum OwnedBridgeWait {
    static func until(seconds: Double, _ condition: () -> Bool) -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            usleep(5_000)
        }
        return condition()
    }

    final class Pending<T: Sendable>: @unchecked Sendable {
        private let done = DispatchSemaphore(value: 0)
        private var result: T?
        fileprivate func finish(_ value: T) {
            result = value
            done.signal()
        }
        func wait() -> T {
            done.wait()
            return result!
        }
    }

    static func start<T: Sendable>(_ work: @escaping @Sendable () -> T) -> Pending<T> {
        let pending = Pending<T>()
        DispatchQueue.global(qos: .userInitiated).async { pending.finish(work()) }
        return pending
    }
}

@Suite("Chrome bridge reply ownership", .serialized)
struct BridgePendingRepliesTests {
    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value
        init(_ value: Value) { self.value = value }
        func read() -> Value { lock.withLock { value } }
        func change(_ update: (inout Value) -> Void) { lock.withLock { update(&value) } }
    }

    private func eventually(_ condition: @Sendable () -> Bool) {
        let met = OwnedBridgeWait.until(seconds: 2, condition)
        #expect(met)
    }

    @Test func duplicateProtocolRequestGetsItsOwnErrorWhileOriginalReplyAndBothSocketsComplete() throws {
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
        let original = OwnedBridgeWait.start { UnixSocket.request(path: path, payload: request, expectReply: true, timeout: 3) }
        eventually { pending.count == 1 && forwarded.read() == 1 }
        let duplicateBytes = UnixSocket.request(path: path, payload: request, expectReply: true, timeout: 3)
        let duplicate = try JSONDecoder().decode(BridgeResponse.self, from: #require(duplicateBytes))
        #expect(duplicate.id == "same-id" && !duplicate.ok && duplicate.error?.code == "duplicate_request")
        #expect(pending.count == 1)
        #expect(forwarded.read() == 1, "Only the original request may be forwarded to Chrome")
        let success = BridgeResponse.success("same-id", .object(["original": .bool(true)]))
        #expect(pending.complete(success))
        let originalBytes = original.wait()
        #expect(try JSONDecoder().decode(BridgeResponse.self, from: #require(originalBytes)) == success)
        #expect(!pending.complete(success))
        eventually { pending.count == 0 && server.activeConnectionCount == 0 }
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

    @Test func aLiveReservationDeadlineProducesOneTimeoutReply() throws {
        let pending = BridgePendingReplies()
        let replies = Box<[Data?]>([])
        let token = try #require(pending.reserve(id: "deadline") { data in replies.change { $0.append(data) } })
        #expect(pending.armTimeout(id: "deadline", token: token, after: 0.03))
        eventually { replies.read().count == 1 }
        let item = try #require(replies.read().first)
        let response = try JSONDecoder().decode(BridgeResponse.self, from: #require(item))
        #expect(response.error?.code == "timeout" && pending.count == 0)
        #expect(!pending.complete(.success("deadline"), token: token))
    }

    /// The bridge socket admits a same-user peer inside the 3 second timeout already on main.
    /// The kernel has to name that peer. A missing identity is a refusal, and the request ends with no reply.
    @Test func aSameUserPeerIsAdmittedInsideTheExistingSocketDeadline() throws {
        var pair = [Int32](repeating: 0, count: 2)
        #if canImport(Darwin)
        let stream = SOCK_STREAM
        #else
        let stream = Int32(SOCK_STREAM.rawValue)
        #endif
        try #require(socketpair(AF_UNIX, stream, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        #expect(PeerCheck.identify(fd: pair[0])?.uid == UInt32(geteuid()))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-br-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("peer.sock").path
        let server = UnixSocketServer(path: path) { _, reply in
            reply(Data("{\"ok\":true}".utf8))
        }
        try server.start()
        defer { server.stop() }
        let reply = UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 3)
        #expect(reply == Data("{\"ok\":true}".utf8))
    }

}
