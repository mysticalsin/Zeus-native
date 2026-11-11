/// The live speech recorder's phase, as one value the locked `SpeechInput` class consults.
///
/// It was spread over `stopRequested`, `consecutiveErrors` and the generation counter, with the restart
/// decisions written twice (after a final result, after an error). The phases:
/// `idle` (never started), `recording(session)`, `restarting(session)` (Apple ended an utterance or
/// failed while the key is still held; a fresh request is being opened) and `stopping(session)` (the
/// person released the key, a cap was hit, the input changed or the turn was cancelled).
/// Every event names the session it belongs to, and an event from an older session changes nothing.
public enum SpeechRecorder {
    public enum State: Equatable, Sendable {
        case idle
        case recording(session: Int, errors: Int)
        case restarting(session: Int, errors: Int)
        case stopping(session: Int)

        public var session: Int? {
            switch self {
            case .idle: nil
            case .recording(let session, _), .restarting(let session, _), .stopping(let session): session
            }
        }

        /// What the old `stopRequested` flag meant: no more audio is wanted for this session.
        public var isStopping: Bool { if case .stopping = self { true } else { false } }
    }

    public enum Event: Equatable, Sendable {
        /// A fresh turn began (the engine is new and the session number moved on).
        case started(session: Int)
        /// Release, cancel, a capture cap or an input change. `session` is the current one.
        case stopRequested(session: Int)
        /// A recognition result with text arrived: the run of errors ends.
        case resultArrived(session: Int)
        /// Apple reported a final result for this utterance.
        case utteranceEnded(session: Int)
        /// Apple reported an error and no final result.
        case recognitionFailed(session: Int, maxRestarts: Int)
        /// The task for the fresh request is installed.
        case taskInstalled(session: Int)
    }

    public enum Effect: Equatable, Sendable {
        /// Fold the text so far into the final text and open a fresh request and task.
        case restart
        /// The turn is over: release whoever waits for the transcript.
        case finishTurn
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .started(let session):
            return (.recording(session: session, errors: 0), [])

        case .stopRequested(let session):
            return (.stopping(session: session), [])

        case .resultArrived(let session):
            switch state {
            case .recording(let current, _) where current == session: return (.recording(session: current, errors: 0), [])
            case .restarting(let current, _) where current == session: return (.restarting(session: current, errors: 0), [])
            default: return (state, [])
            }

        case .utteranceEnded(let session):
            switch state {
            case .recording(let current, let errors) where current == session:
                return (.restarting(session: current, errors: errors), [.restart])
            case .stopping(let current) where current == session:
                return (state, [.finishTurn])
            default:
                return (state, [])
            }

        case .recognitionFailed(let session, let maxRestarts):
            switch state {
            case .recording(let current, let errors) where current == session:
                guard errors < maxRestarts else { return (state, [.finishTurn]) }
                return (.restarting(session: current, errors: errors + 1), [.restart])
            case .stopping(let current) where current == session:
                return (state, [.finishTurn])
            default:
                return (state, [])
            }

        case .taskInstalled(let session):
            guard case .restarting(let current, let errors) = state, current == session else { return (state, []) }
            return (.recording(session: current, errors: errors), [])
        }
    }
}
