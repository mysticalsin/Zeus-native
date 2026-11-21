import Foundation

/// How one provider clip leaves the gate. Finish, cancel, and failure each release that clip once.
public enum ProviderClipResolution: Equatable, Sendable {
    case finished
    case cancelled
    case failed
}

/// Events for one playback gate. A clip stays live until its own token is finished, cancelled, or failed.
public enum ProviderPlaybackEvent: Equatable, Sendable {
    case begin
    case beginPlayer(ObjectIdentifier)
    case finished(Int)
    case cancelled(Int)
    case failed(Int)
    case endPlayer(ObjectIdentifier)
    case reset
}

/// Per-clip tokens. The gate is open only when no token is live, including when clips overlap.
public struct ProviderPlaybackMachine: Equatable, Sendable {
    private struct LiveClip: Equatable, Sendable {
        var player: ObjectIdentifier?
    }

    private var generation = 0
    private var live: [Int: LiveClip] = [:]
    private var players: [ObjectIdentifier: Int] = [:]

    public init() {}

    /// Live clips. The gate is open exactly when this is zero.
    public var active: Int { live.count }
    public var isPlaying: Bool { active > 0 }
    public var isOpen: Bool { active == 0 }

    @discardableResult
    public mutating func reduce(_ event: ProviderPlaybackEvent) -> Int? {
        switch event {
        case .begin:
            return issue(nil)
        case .beginPlayer(let id):
            return issue(id)
        case .finished(let token):
            release(token, .finished)
            return nil
        case .cancelled(let token):
            release(token, .cancelled)
            return nil
        case .failed(let token):
            release(token, .failed)
            return nil
        case .endPlayer(let id):
            guard let token = players[id] else { return nil }
            release(token, .finished)
            if players[id] == token { players.removeValue(forKey: id) }
            return nil
        case .reset:
            live.removeAll()
            players.removeAll()
            generation += 1
            return nil
        }
    }

    private mutating func issue(_ player: ObjectIdentifier?) -> Int {
        generation += 1
        let token = generation
        live[token] = LiveClip(player: player)
        if let player { players[player] = token }
        return token
    }

    /// Each resolution drops that token once. A second resolution, or a token from before `reset`, does nothing.
    private mutating func release(_ token: Int, _ resolution: ProviderClipResolution) {
        guard let clip = live.removeValue(forKey: token) else { return }
        switch resolution {
        case .finished, .cancelled, .failed:
            if let player = clip.player, players[player] == token {
                players.removeValue(forKey: player)
            }
        }
    }
}

/// Whether a cloud provider clip is still playing. The sentence pump and `isSpeaking` both read it,
/// so the next line does not start until every overlapping clip has finished, been cancelled, or failed.
public final class ProviderPlaybackGate: @unchecked Sendable {
    public static let shared = ProviderPlaybackGate()
    private let lock = NSLock()
    private var machine = ProviderPlaybackMachine()

    public init() {}

    public var active: Int {
        lock.lock(); defer { lock.unlock() }
        return machine.active
    }

    public var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return machine.isPlaying
    }

    /// The next queued line may start. This is true exactly when `active` is zero.
    public var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return machine.isOpen
    }

    @discardableResult
    public func begin() -> Int {
        lock.lock(); defer { lock.unlock() }
        return issued(.begin)
    }

    @discardableResult
    public func begin(player id: ObjectIdentifier) -> Int {
        lock.lock(); defer { lock.unlock() }
        return issued(.beginPlayer(id))
    }

    public func end(_ token: Int) {
        end(token, .finished)
    }

    public func end(_ token: Int, _ resolution: ProviderClipResolution) {
        lock.lock(); defer { lock.unlock() }
        switch resolution {
        case .finished:
            _ = machine.reduce(.finished(token))
        case .cancelled:
            _ = machine.reduce(.cancelled(token))
        case .failed:
            _ = machine.reduce(.failed(token))
        }
    }

    public func cancel(_ token: Int) {
        end(token, .cancelled)
    }

    public func fail(_ token: Int) {
        end(token, .failed)
    }

    public func endPlayer(_ id: ObjectIdentifier) {
        lock.lock(); defer { lock.unlock() }
        _ = machine.reduce(.endPlayer(id))
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        _ = machine.reduce(.reset)
    }

    private func issued(_ event: ProviderPlaybackEvent) -> Int {
        guard let token = machine.reduce(event) else {
            preconditionFailure("begin issues a token")
        }
        return token
    }
}

/// The pump's two questions: may the next queued line start, and is any audio still going.
public enum ProviderSentencePump {
    public static func canDequeue(queueEmpty: Bool, providerPlaying: Bool) -> Bool {
        !queueEmpty && !providerPlaying
    }

    public static func holds(chainPlaying: Bool, systemRendering: Bool, providerPlaying: Bool) -> Bool {
        chainPlaying || systemRendering || providerPlaying
    }

    public static func isSpeaking(synthesizer: Bool, pump: Bool, chainPlaying: Bool, systemRendering: Bool, providerPlaying: Bool) -> Bool {
        synthesizer || pump || holds(chainPlaying: chainPlaying, systemRendering: systemRendering, providerPlaying: providerPlaying)
    }
}
