/// One Polyglot run, from Start to Stop, as a single state.
///
/// The controller kept `isStarting` and `isListening` as two Bools next to a generation counter and
/// guarded every await by hand. That was correct, but an input ending while the run was still
/// starting (the microphone changed during the system-audio start) was lost: the run then reported
/// "listening" on a dead input. Every input event now carries the run's token, and an input that
/// ended before the start finished is never counted as open.
public enum PolyglotRun {
    public enum Input: Hashable, Sendable { case microphone, system }

    public enum State: Equatable, Sendable {
        case idle
        /// Opening inputs. `opened` are running, `ended` stopped on their own before the start finished.
        case starting(token: Int, opened: Set<Input>, ended: Set<Input>, notes: [String])
        case listening(token: Int, open: Set<Input>)
        /// Stop was pressed; the last utterance is draining. A new start may begin while it drains.
        case stopping(token: Int)

        public var isStarting: Bool { if case .starting = self { true } else { false } }
        public var isListening: Bool { if case .listening = self { true } else { false } }
        /// Starting or listening: audio may be flowing.
        public var isActive: Bool { isStarting || isListening }

        public func isStarting(token: Int) -> Bool {
            if case .starting(let current, _, _, _) = self { return current == token }
            return false
        }
    }

    public enum Event: Equatable, Sendable {
        /// Start pressed. `token` identifies this run.
        case startRequested(token: Int)
        /// The speech engine could not be prepared (before any input opened).
        case startFailed(token: Int, message: String)
        case inputOpened(token: Int, input: Input)
        case inputFailed(token: Int, input: Input, message: String)
        /// An input stopped on its own (device changed, Mac audio ended).
        case inputEnded(token: Int, input: Input, message: String)
        /// Every requested input has been tried.
        case startSettled(token: Int)
        /// Stop pressed, or the feature turned off. `token` is the new, newer-than-everything token.
        case stopRequested(token: Int)
        /// The run that was stopping with `token` finished draining.
        case drained(token: Int)
    }

    public enum Effect: Equatable, Sendable {
        /// Stop this input's capture now (the stored one, or the one that has just opened).
        case release(Input)
        /// The last input is gone: end the run.
        case endRun
        /// The start finished with at least one input open.
        case began(notes: [String])
        /// The start finished with no input open.
        case aborted(notes: [String])
        /// A start that was already replaced finished: throw away what it made.
        case discarded
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .startRequested(let token):
            switch state {
            case .idle, .stopping:
                return (.starting(token: token, opened: [], ended: [], notes: []), [])
            case .starting, .listening:
                return (state, [])
            }

        case .startFailed(let token, let message):
            guard state.isStarting(token: token) else { return (state, [.discarded]) }
            return (.idle, [.aborted(notes: [message])])

        case .inputOpened(let token, let input):
            guard case .starting(let current, var opened, let ended, let notes) = state, current == token else {
                return (state, [.release(input)])
            }
            if ended.contains(input) { return (state, [.release(input)]) }
            opened.insert(input)
            return (.starting(token: current, opened: opened, ended: ended, notes: notes), [])

        case .inputFailed(let token, _, let message):
            guard case .starting(let current, let opened, let ended, var notes) = state, current == token else { return (state, []) }
            notes.append(message)
            return (.starting(token: current, opened: opened, ended: ended, notes: notes), [])

        case .inputEnded(let token, let input, let message):
            switch state {
            case .starting(let current, var opened, var ended, var notes) where current == token:
                let wasOpen = opened.remove(input) != nil
                ended.insert(input)
                notes.append(message)
                return (.starting(token: current, opened: opened, ended: ended, notes: notes), wasOpen ? [.release(input)] : [])
            case .listening(let current, var open) where current == token:
                guard open.remove(input) != nil else { return (state, []) }
                return (.listening(token: current, open: open), open.isEmpty ? [.release(input), .endRun] : [.release(input)])
            default:
                return (state, [])
            }

        case .startSettled(let token):
            guard case .starting(let current, let opened, _, let notes) = state, current == token else { return (state, [.discarded]) }
            if opened.isEmpty { return (.idle, [.aborted(notes: notes)]) }
            return (.listening(token: current, open: opened), [.began(notes: notes)])

        case .stopRequested(let token):
            switch state {
            case .idle: return (.idle, [])
            case .starting, .listening: return (.stopping(token: token), [])
            case .stopping: return (state, [])
            }

        case .drained(let token):
            guard case .stopping(let current) = state, current == token else { return (state, []) }
            return (.idle, [])
        }
    }
}
