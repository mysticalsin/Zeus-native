import Foundation
import Testing
import ZeusCore

@Suite("Brain race")
struct RouterRaceTests {
    @Test func theFastProviderWinsAndTheSlowOneIsCancelled() async throws {
        let cancelled = CancelBox()
        let fast = stream(id: "fast", delayMs: 10, token: "A", cancel: cancelled)
        let slow = stream(id: "slow", delayMs: 2_000, token: "B", cancel: cancelled)
        let race = BrainRace.compete([fast, slow]) { id in cancelled.mark(id) }
        let started = ContinuousClock.now
        var text = ""
        for try await event in race.events {
            if case .textDelta(let delta) = event { text += delta }
            if case .done = event { break }
        }
        let elapsed = ContinuousClock.now - started
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        #expect(race.winner.winnerID == "fast")
        #expect(text.hasPrefix("A"))
        #expect(cancelled.ids.contains("slow"))
        // Wall clock under swarm lock load; still orders of magnitude below the 2 s slow path.
        #expect(ms < 500)
        #expect(race.winner.milliseconds < 500)
    }

    @Test func frontPairStartsTogether() async throws {
        let cancelled = CancelBox()
        let slow = stream(id: "slow", delayMs: 600, token: "S", cancel: cancelled)
        let fast = stream(id: "fast", delayMs: 40, token: "F", cancel: cancelled)
        let race = BrainRace.competeStaggered([slow, fast], staggerMs: 1_500) { id in cancelled.mark(id) }
        var text = ""
        for try await event in race.events {
            if case .textDelta(let delta) = event { text += delta }
            if case .done = event { break }
        }
        #expect(race.winner.winnerID == "fast")
        #expect(text.hasPrefix("F"))
        #expect(race.winner.milliseconds < 500)
    }

    @Test func thirdEngineWaitsOutTheStagger() async throws {
        let cancelled = CancelBox()
        let first = stream(id: "a", delayMs: 2_000, token: "A", cancel: cancelled)
        let second = stream(id: "b", delayMs: 2_000, token: "B", cancel: cancelled)
        let third = stream(id: "c", delayMs: 30, token: "C", cancel: cancelled)
        let race = BrainRace.competeStaggered([first, second, third], staggerMs: 250) { id in cancelled.mark(id) }
        var text = ""
        for try await event in race.events {
            if case .textDelta(let delta) = event { text += delta }
            if case .done = event { break }
        }
        #expect(race.winner.winnerID == "c")
        #expect(text.hasPrefix("C"))
        #expect(race.winner.milliseconds > 180)
        #expect(race.winner.milliseconds < 1_200)
    }

    private final class CancelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        var ids: [String] { lock.withLock { values } }
        func mark(_ id: String) { lock.withLock { values.append(id) } }
    }

    private func stream(id: String, delayMs: Int, token: String, cancel: CancelBox) -> (id: String, events: AsyncThrowingStream<BrainEvent, Error>) {
        let events = AsyncThrowingStream<BrainEvent, Error> { continuation in
            let task = Task {
                try await Task.sleep(for: .milliseconds(delayMs))
                continuation.yield(.textDelta(token))
                continuation.yield(.done(nil))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                cancel.mark(id)
            }
        }
        return (id, events)
    }
}
