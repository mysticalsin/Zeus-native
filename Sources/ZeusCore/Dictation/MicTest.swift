/// Settings > Dictation > Test microphone as one state.
///
/// It used to be four loose values (`running`, `level`, `peak`, `problem`) plus an engine and a stop
/// timer, and the level tap only checked `running`: a level queued from a test that had just ended
/// could land in the next test and inflate its peak, so the verdict ("Too quiet", "Good") was wrong.
/// Every level now carries the session it was measured in, and only the live session may move the state.
public enum MicTest {
    public enum State: Equatable, Sendable {
        case idle
        case running(session: UInt64, level: Double, peak: Double, note: String?)
        /// The test ended; its loudest level stays for the verdict.
        case finished(peak: Double, note: String?)
        case failed(String)

        public var isRunning: Bool {
            if case .running = self { return true }
            return false
        }

        public var level: Double {
            if case .running(_, let level, _, _) = self { return level }
            return 0
        }

        public var peak: Double {
            switch self {
            case .running(_, _, let peak, _), .finished(let peak, _): peak
            case .idle, .failed: 0
            }
        }

        /// A problem, or a note such as "using the system input" that does not stop the test.
        public var problem: String? {
            switch self {
            case .running(_, _, _, let note), .finished(_, let note): note
            case .failed(let problem): problem
            case .idle: nil
            }
        }

        /// Only once the test has ended with something heard.
        public var verdict: String? { isRunning || peak == 0 ? nil : MicLevel.verdict(peak: peak) }
    }

    public enum Event: Equatable, Sendable {
        /// The engine for `session` is running.
        case opened(session: UInt64, note: String?)
        /// The engine for `session` could not start.
        case failed(session: UInt64, problem: String)
        case level(session: UInt64, value: Double)
        case stopRequested
        /// The test's own timer for `session` ran out.
        case timedOut(session: UInt64)
    }

    public enum Effect: Equatable, Sendable {
        /// Remove the tap, stop the engine and cancel the timer.
        case stopCapture
        /// A second engine opened while one was running: tear the new one down.
        case discardCapture(session: UInt64)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .opened(let session, let note):
            guard !state.isRunning else { return (state, [.discardCapture(session: session)]) }
            return (.running(session: session, level: 0, peak: 0, note: note), [])

        case .failed(_, let problem):
            // A failed start never replaces a test that is running.
            guard !state.isRunning else { return (state, []) }
            return (.failed(problem), [])

        case .level(let session, let value):
            guard case .running(let live, _, let peak, let note) = state, live == session else { return (state, []) }
            return (.running(session: live, level: value, peak: max(peak, value), note: note), [])

        case .stopRequested:
            guard case .running(_, _, let peak, let note) = state else { return (state, []) }
            return (.finished(peak: peak, note: note), [.stopCapture])

        case .timedOut(let session):
            guard case .running(let live, _, let peak, let note) = state, live == session else { return (state, []) }
            return (.finished(peak: peak, note: note), [.stopCapture])
        }
    }
}
