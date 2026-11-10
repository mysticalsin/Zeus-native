import Foundation

/// Owns each forwarded Chrome request until its response or its own timeout settles it.
/// Duplicate IDs receive an error on their own connection and never replace the original reply.
public final class BridgePendingReplies: @unchecked Sendable {
    private struct Entry {
        let token: UUID
        let reply: UnixSocketServer.Reply
    }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    var count: Int { lock.withLock { entries.count } }

    /// The token binds a delayed timeout to this reservation, even if the ID is reused later.
    public func reserve(id: String, reply: @escaping UnixSocketServer.Reply) -> UUID? {
        let token = lock.withLock { () -> UUID? in
            guard entries[id] == nil else { return nil }
            let token = UUID()
            entries[id] = Entry(token: token, reply: reply)
            return token
        }
        if token == nil {
            reply(try? JSONEncoder().encode(BridgeResponse.failure(id, BridgeError(
                code: "duplicate_request", message: "A request with this ID is already pending"))))
        }
        return token
    }

    /// Returns false for a missing/already completed request or an older reservation's timeout.
    /// User callbacks always execute after releasing the registry lock.
    @discardableResult
    public func complete(_ response: BridgeResponse, token: UUID? = nil) -> Bool {
        let reply = lock.withLock { () -> UnixSocketServer.Reply? in
            guard let entry = entries[response.id], token == nil || entry.token == token else { return nil }
            entries.removeValue(forKey: response.id)
            return entry.reply
        }
        guard let reply else { return false }
        reply(try? JSONEncoder().encode(response))
        return true
    }
}
