import Foundation

/// Whether a cloud provider clip is still playing. The sentence pump and `isSpeaking` both read it,
/// so the next line does not start until this clip ends.
public final class ProviderPlaybackGate: @unchecked Sendable {
    public static let shared = ProviderPlaybackGate()
    private let lock = NSLock()
    private var depth = 0
    private var generation = 0
    private var players: [ObjectIdentifier: Int] = [:]

    public init() {}

    public var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return depth > 0
    }

    @discardableResult
    public func begin() -> Int {
        lock.lock(); defer { lock.unlock() }
        depth += 1
        generation += 1
        return generation
    }

    @discardableResult
    public func begin(player id: ObjectIdentifier) -> Int {
        lock.lock(); defer { lock.unlock() }
        depth += 1
        generation += 1
        players[id] = generation
        return generation
    }

    public func end(_ token: Int) {
        lock.lock(); defer { lock.unlock() }
        guard token == generation, depth > 0 else { return }
        depth -= 1
    }

    public func endPlayer(_ id: ObjectIdentifier) {
        lock.lock(); defer { lock.unlock() }
        guard let token = players.removeValue(forKey: id) else { return }
        guard token == generation, depth > 0 else { return }
        depth -= 1
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        depth = 0
        generation += 1
        players.removeAll()
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
