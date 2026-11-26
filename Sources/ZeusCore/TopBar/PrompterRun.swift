/// The teleprompter's run and its voice-follow microphone as one state.
///
/// `begin`, `end`, `setVoice` and the microphone's level callback each changed their own flags. A
/// level queued by the tap just before `end()` landed after the reset to zero and lit the meter again,
/// and the same thing happened across a voice-follow off and on. Every microphone start now has a
/// session number, and a level is accepted only from the live session of a running prompter.
///
/// Each answer is read from `PrompterRunBox`. This type does not start a microphone.
public enum PrompterRun {
    public enum State: Equatable, Sendable {
        case idle
        /// `mic` is the session of the live voice-follow microphone, nil when the script scrolls at a steady pace.
        case running(mic: Int?)

        public var isRunning: Bool { PrompterRunBox.isRunning(phase) }

        /// A level from the microphone of `session` may move the meter and the scroll.
        public func acceptsLevel(from session: Int) -> Bool {
            PrompterRunBox.acceptsLevel(phase, from: session)
        }

        fileprivate var phase: PrompterRunBox.Phase {
            switch self {
            case .idle: return .idle
            case .running(let mic): return .running(mic: mic)
            }
        }

        fileprivate init(_ phase: PrompterRunBox.Phase) {
            switch phase {
            case .idle: self = .idle
            case .running(let mic): self = .running(mic: mic)
            }
        }
    }

    public enum Event: Equatable, Sendable {
        case began(voiceFollow: Bool, session: Int)
        case ended
        /// The Voice follow switch changed while the prompter may be running.
        case voiceChanged(on: Bool, session: Int)
        /// The microphone for `session` could not start or died.
        case micFailed(session: Int)

        fileprivate var step: PrompterRunBox.Step {
            switch self {
            case .began(let voiceFollow, let session):
                return .began(voiceFollow: voiceFollow, session: session)
            case .ended:
                return .ended
            case .voiceChanged(let on, let session):
                return .voiceChanged(on: on, session: session)
            case .micFailed(let session):
                return .micFailed(session: session)
            }
        }
    }

    public enum Effect: Equatable, Sendable {
        case startMic(session: Int)
        case stopMic

        fileprivate init(_ effect: PrompterRunBox.Effect) {
            switch effect {
            case .startMic(let session): self = .startMic(session: session)
            case .stopMic: self = .stopMic
            }
        }
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        let (phase, effects) = PrompterRunBox.reduce(state.phase, event.step)
        return (State(phase), effects.map(Effect.init))
    }
}
