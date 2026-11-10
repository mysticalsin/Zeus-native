import Foundation
import Testing
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
        let original = Task.detached { UnixSocket.request(path: path, payload: request, expectReply: true, timeout: 3) }
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
}
