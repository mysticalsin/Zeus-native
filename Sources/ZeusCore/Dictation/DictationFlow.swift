/// What the notch shows for dictation. The top bar only reads this.
public enum DictationPhase: Equatable, Sendable {
    case idle, listening, transcribing, rewriting, done, failed(String)
}

/// The whole life of one dictation job (a live turn, a transcribed file, a history re-run) as one state.
///
/// Before this, `topBar.dictationPhase` was written from about twenty places and nothing stopped two
/// kinds of job overlapping: "Transcribe a file" while the microphone was open overwrote `.listening`
/// with `.transcribing`, so the mic kept recording under a phase that no longer allowed finishing it;
/// a second file started over the first, and whichever finished first showed "done" while the other
/// was still running. Now a job can begin only from idle, done or failed; every completion carries the
/// turn token it started with and is dropped if the state has moved on; and cancel from any active
/// state returns to idle and says what to release.
public enum DictationFlow {
    public enum Source: Equatable, Sendable {
        /// Microphone turn: listening, then transcribing the captured audio.
        case live
        /// A file picked for transcription.
        case file
        /// A history entry run again with another mode or engine.
        case history
    }

    public enum State: Equatable, Sendable {
        case idle
        case listening(turn: UInt64)
        case transcribing(turn: UInt64, source: Source)
        case rewriting(turn: UInt64, source: Source)
        case done
        case failed(String)

        /// Done and failed are results waiting to be replaced, not active jobs.
        public var canStartJob: Bool {
            switch self {
            case .idle, .done, .failed: true
            case .listening, .transcribing, .rewriting: false
            }
        }

        public var isActive: Bool { !canStartJob }

        public var phase: DictationPhase {
            switch self {
            case .idle: .idle
            case .listening: .listening
            case .transcribing: .transcribing
            case .rewriting: .rewriting
            case .done: .done
            case .failed(let reason): .failed(reason)
            }
        }

        /// The token of the active job, if any.
        public var turn: UInt64? {
            switch self {
            case .listening(let turn), .transcribing(let turn, _), .rewriting(let turn, _): turn
            case .idle, .done, .failed: nil
            }
        }

        public var isListening: Bool {
            if case .listening = self { return true }
            return false
        }
    }

    public enum Event: Equatable, Sendable {
        /// The microphone opened for `turn`.
        case micOpened(turn: UInt64)
        /// A live turn could not start (no permission, no engine, the recorder threw).
        case startFailed(reason: String)
        /// Key released or toggled: stop listening and transcribe.
        case finishRequested
        /// A file was picked.
        case fileRequested(turn: UInt64)
        /// The AI rewrite began. From a live turn this follows transcribing; a history re-run enters here directly.
        case rewriteStarted(turn: UInt64, source: Source)
        /// The job for `turn` produced its result.
        case succeeded(turn: UInt64)
        /// The job for `turn` ended with a problem worth showing.
        case failed(turn: UInt64, reason: String)
        /// The job for `turn` ended with nothing to show (discarded, or a history re-run finished quietly).
        case dismissed(turn: UInt64)
        /// Escape, the cancel hotkey or a new owner: stop whatever is running.
        case cancelRequested
    }

    public enum Effect: Equatable, Sendable {
        /// Release capture, taps, streams and queued partials for the job that was running.
        case releaseCapture
        /// Drop everything the old turn token still owns, so its late completions find nothing.
        case invalidateTurn
        /// A new job was refused because one is already running.
        case busy
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .micOpened(let turn):
            guard state.canStartJob else { return (state, [.busy]) }
            return (.listening(turn: turn), [])

        case .startFailed(let reason):
            // A failed start never replaces a job that is already running.
            guard state.canStartJob else { return (state, []) }
            return (.failed(reason), [])

        case .finishRequested:
            guard case .listening(let turn) = state else { return (state, []) }
            return (.transcribing(turn: turn, source: .live), [])

        case .fileRequested(let turn):
            guard state.canStartJob else { return (state, [.busy]) }
            return (.transcribing(turn: turn, source: .file), [])

        case .rewriteStarted(let turn, let source):
            switch (state, source) {
            case (.transcribing(let live, .live), .live) where live == turn:
                return (.rewriting(turn: turn, source: .live), [])
            case (_, .history) where state.canStartJob:
                return (.rewriting(turn: turn, source: .history), [])
            default:
                return (state, [])
            }

        case .succeeded(let turn):
            guard state.turn == turn, !state.isListening else { return (state, []) }
            return (.done, [])

        case .failed(let turn, let reason):
            guard state.turn == turn, !state.isListening else { return (state, []) }
            return (.failed(reason), [])

        case .dismissed(let turn):
            guard state.turn == turn, !state.isListening else { return (state, []) }
            return (.idle, [])

        case .cancelRequested:
            switch state {
            case .listening, .transcribing, .rewriting: return (.idle, [.invalidateTurn, .releaseCapture])
            case .idle, .done, .failed: return (state, [])
            }
        }
    }
}
