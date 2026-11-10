import Foundation

/// The first engine to produce a word wins. The others are cancelled.
public enum BrainRace {
    public enum RaceError: Error { case noToken }

    public final class Winner: @unchecked Sendable {
        private let lock = NSLock()
        private var id: String?
        private var ms = 0

        public var winnerID: String? { lock.withLock { id } }
        public var milliseconds: Int { lock.withLock { ms } }

        func claim(_ id: String, milliseconds: Int) -> Bool {
            lock.withLock {
                if self.id != nil { return false }
                self.id = id
                self.ms = milliseconds
                return true
            }
        }
    }

    /// The most recent real failure from a racer, kept so a race with no winner reports why
    /// (quota, signed out, timeout) instead of a bare "no token".
    final class LastFailure: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Error?
        func record(_ error: Error) { lock.withLock { stored = error } }
        var error: Error? { lock.withLock { stored } }
    }

    /// Milliseconds before starting the next engine when the prior one has not produced a token (R24).
    public static let staggerMs = 1_500

    /// The front two engines start together. Each engine after that waits `staggerMs` more
    /// before it is asked for a token, so a slow first token does not block the next one
    /// and a dead engine does not hold the whole turn.
    public static func competeStaggered(
        _ racers: [(id: String, events: AsyncThrowingStream<BrainEvent, Error>)],
        staggerMs: Int = staggerMs,
        cancel: @escaping @Sendable (String) -> Void
    ) -> (winner: Winner, events: AsyncThrowingStream<BrainEvent, Error>) {
        guard racers.count >= 2 else { return compete(racers, cancel: cancel) }
        let lead = min(2, racers.count)
        let delayed: [(id: String, events: AsyncThrowingStream<BrainEvent, Error>)] = racers.enumerated().map { index, racer in
            guard index >= lead else { return racer }
            let wait = staggerMs * (index - lead + 1)
            let events = AsyncThrowingStream<BrainEvent, Error> { continuation in
                let task = Task {
                    try? await Task.sleep(for: .milliseconds(wait))
                    if Task.isCancelled { continuation.finish(); return }
                    do {
                        for try await event in racer.events {
                            if Task.isCancelled { break }
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            return (racer.id, events)
        }
        return compete(delayed, cancel: cancel)
    }

    /// `events` yields the winner's stream from its first delta, including that delta.
    public static func compete(
        _ racers: [(id: String, events: AsyncThrowingStream<BrainEvent, Error>)],
        cancel: @escaping @Sendable (String) -> Void
    ) -> (winner: Winner, events: AsyncThrowingStream<BrainEvent, Error>) {
        let winner = Winner()
        let failure = LastFailure()
        let started = ContinuousClock.now
        let events = AsyncThrowingStream<BrainEvent, Error> { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for racer in racers {
                        group.addTask {
                            do {
                                for try await event in racer.events {
                                    if Task.isCancelled { return }
                                    if case .textDelta(let text) = event, !text.isEmpty {
                                        let elapsed = Self.milliseconds(since: started)
                                        if winner.claim(racer.id, milliseconds: elapsed) {
                                            for other in racers where other.id != racer.id { cancel(other.id) }
                                            continuation.yield(event)
                                        } else if winner.winnerID == racer.id {
                                            continuation.yield(event)
                                        } else {
                                            return
                                        }
                                    } else if winner.winnerID == racer.id {
                                        continuation.yield(event)
                                    }
                                }
                                if winner.winnerID == racer.id { continuation.finish() }
                            } catch {
                                if winner.winnerID == racer.id { continuation.finish(throwing: error) } else { failure.record(error) }
                            }
                        }
                    }
                }
                if winner.winnerID == nil { continuation.finish(throwing: failure.error ?? RaceError.noToken) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (winner, events)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = ContinuousClock.now - start
        return Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
    }
}
