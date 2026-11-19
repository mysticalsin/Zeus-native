/// The teleprompter's run and its voice-follow microphone as one state.
///
/// `begin`, `end`, `setVoice` and the microphone's level callback each changed their own flags. A
/// level queued by the tap just before `end()` landed after the reset to zero and lit the meter again,
/// and the same thing happened across a voice-follow off and on. Every microphone start now has a
/// session number, and a level is accepted only from the live session of a running prompter.
public enum PrompterRun {
    public enum State: Equatable, Sendable {
        case idle
        /// `mic` is the session of the live voice-follow microphone, nil when the script scrolls at a steady pace.
        case running(mic: Int?)

        public var isRunning: Bool { if case .running = self { return true } else { return false } }

        /// A level from the microphone of `session` may move the meter and the scroll.
        public func acceptsLevel(from session: Int) -> Bool {
            if case .running(let mic) = self { return mic == session }
            return false
        }
    }

    public enum Event: Equatable, Sendable {
        case began(voiceFollow: Bool, session: Int)
        case ended
        /// The Voice follow switch changed while the prompter may be running.
        case voiceChanged(on: Bool, session: Int)
        /// The microphone for `session` could not start or died.
        case micFailed(session: Int)
    }

    public enum Effect: Equatable, Sendable {
        case startMic(session: Int)
        case stopMic
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .began(let voiceFollow, let session):
            guard case .idle = state else { return (state, []) }
            return voiceFollow ? (.running(mic: session), [.startMic(session: session)]) : (.running(mic: nil), [])

        case .ended:
            guard case .running(let mic) = state else { return (.idle, []) }
            return (.idle, mic == nil ? [] : [.stopMic])

        case .voiceChanged(let on, let session):
            guard case .running(let mic) = state else { return (state, []) }
            switch (on, mic) {
            case (true, nil): return (.running(mic: session), [.startMic(session: session)])
            case (false, .some): return (.running(mic: nil), [.stopMic])
            default: return (state, [])
            }

        case .micFailed(let session):
            guard case .running(let mic) = state, mic == session else { return (state, []) }
            return (.running(mic: nil), [.stopMic])
        }
    }
}
