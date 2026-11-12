import Foundation

/// Owns each forwarded Chrome request until its response or its own timeout settles it.
/// Duplicate IDs receive an error on their own connection and never replace the original reply.
public final class BridgePendingReplies: @unchecked Sendable {
    private struct Entry {
        let token: UUID
        let reply: UnixSocketServer.Reply
        var timer: DispatchSourceTimer?
    }
    private let lock = NSLock()
    private let timerQueue = DispatchQueue(label: "zeus.bridge.deadlines", qos: .utility)
    private var entries: [String: Entry] = [:]

    public init() {}

    var count: Int { lock.withLock { entries.count } }

    /// The token binds a delayed timeout to this reservation, even if the ID is reused later.
    public func reserve(id: String, reply: @escaping UnixSocketServer.Reply) -> UUID? {
        let token = lock.withLock { () -> UUID? in
            guard entries[id] == nil else { return nil }
            let token = UUID()
            entries[id] = Entry(token: token, reply: reply, timer: nil)
            return token
        }
        if token == nil {
            reply(try? JSONEncoder().encode(BridgeResponse.failure(id, BridgeError(
                code: "duplicate_request", message: "A request with this ID is already pending"))))
        }
        return token
    }

    /// One cancelable timer belongs to a live reservation. Completed requests do not leave
    /// delayed work items retaining IDs/closures until the old sixty-second deadline.
    @discardableResult
    public func armTimeout(id: String, token: UUID, after seconds: TimeInterval) -> Bool {
        guard seconds.isFinite, seconds > 0, seconds <= 3_600 else { return false }
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            self?.complete(.failure(id, BridgeError(code: "timeout", message: "Chrome did not answer in time")), token: token)
        }
        let armed = lock.withLock { () -> Bool in
            guard var entry = entries[id], entry.token == token, entry.timer == nil else { return false }
            entry.timer = timer
            entries[id] = entry
            return true
        }
        if !armed { timer.cancel() }
        timer.resume()
        return armed
    }

    /// A broken native stream cannot settle requests later. Detach all callbacks atomically,
    /// then call each once outside the lock; the socket transport owns bounded reply delivery.
    public func failAll(_ error: BridgeError) {
        let pending = lock.withLock { () -> [String: Entry] in
            let result = entries
            entries.removeAll()
            return result
        }
        for (id, entry) in pending {
            entry.timer?.cancel()
            entry.reply(try? JSONEncoder().encode(BridgeResponse.failure(id, error)))
        }
    }

    /// Returns false for a missing/already completed request or an older reservation's timeout.
    /// User callbacks always execute after releasing the registry lock.
    @discardableResult
    public func complete(_ response: BridgeResponse, token: UUID? = nil) -> Bool {
        let entry = lock.withLock { () -> Entry? in
            guard let entry = entries[response.id], token == nil || entry.token == token else { return nil }
            entries.removeValue(forKey: response.id)
            return entry
        }
        guard let entry else { return false }
        entry.timer?.cancel()
        entry.reply(try? JSONEncoder().encode(response))
        return true
    }
}
