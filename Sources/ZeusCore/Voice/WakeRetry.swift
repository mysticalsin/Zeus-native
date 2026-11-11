/// When the "Hey Zeus" listener may try to start again after it failed to.
///
/// A single `retryStartAt` date retried every 10 s (microphone did not start) or 30 s (no on-device
/// recognition) forever, and logged the same failure each time. The retry is now a state: it backs off
/// (doubling, capped), gives up after a bounded number of attempts with "needs attention", and starts
/// over only when something changed (turned off and on, a pause such as a missing permission, a
/// success). It is driven by the controller's existing 2 s gate check, never by its own sleep loop.
public enum WakeRetry {
    public enum Failure: Equatable, Sendable {
        /// The microphone did not start (busy, device change). Often passes quickly.
        case microphone
        /// This language has no on-device recognition. Passes only if the person changes something.
        case onDeviceRecognition

        /// Seconds before the first retry.
        var firstDelay: Double { self == .microphone ? 10 : 30 }
        var maxDelay: Double { self == .microphone ? 60 : 120 }
        var maxAttempts: Int { self == .microphone ? 6 : 3 }
    }

    public enum State: Equatable, Sendable {
        case ready
        /// `attempts` failures in a row; the next try is allowed at `retryAt` (seconds, any steady clock).
        case backingOff(failure: Failure, attempts: Int, retryAt: Double)
        /// Retries ran out. Nothing starts until something changes.
        case needsAttention(Failure)
    }

    public enum Event: Equatable, Sendable {
        case failed(Failure, now: Double)
        case started
        /// Something changed: turned off and on, paused for another reason, permissions changed.
        case reset
    }

    public enum Effect: Equatable, Sendable {
        /// First failure of a streak, or a different kind of failure: worth one log line.
        case logFailure(Failure)
        /// The last allowed attempt failed.
        case gaveUp(Failure)
    }

    public static func canTry(_ state: State, now: Double) -> Bool {
        switch state {
        case .ready: true
        case .backingOff(_, _, let retryAt): now >= retryAt
        case .needsAttention: false
        }
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .started, .reset:
            return (.ready, [])

        case .failed(let failure, let now):
            var attempts = 1
            var streak = false
            switch state {
            case .backingOff(let previous, let count, _) where previous == failure:
                attempts = count + 1
                streak = true
            case .needsAttention(let previous) where previous == failure:
                return (state, [])
            default:
                break
            }
            var effects: [Effect] = streak ? [] : [.logFailure(failure)]
            guard attempts < failure.maxAttempts else {
                effects.append(.gaveUp(failure))
                return (.needsAttention(failure), effects)
            }
            let delay = min(failure.firstDelay * Double(1 << (attempts - 1)), failure.maxDelay)
            return (.backingOff(failure: failure, attempts: attempts, retryAt: now + delay), effects)
        }
    }
}
