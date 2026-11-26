import Foundation

/// Session rules for a running teleprompter and its voice-follow microphone.
///
/// A begin while already running changes nothing, including the live microphone session.
/// Ending a run with a live microphone stops that microphone. Ending a steady scroll, or an idle run, has no effect.
/// A level is accepted only from the microphone session that is live. Idle and a steady scroll accept none.
/// Turning voice follow on while scrolling starts the session named by the event.
/// Turning voice follow off stops the live microphone even when the event names a different session.
/// Turning voice follow on when a microphone is already live does nothing, even when the event names a different session.
/// A microphone failure stops only the session that failed, and the run continues without a microphone.
/// A failure for another session, for a steady scroll, or while idle changes nothing.
/// A session number is identity, including zero and negative numbers.
/// This type does not read a screen, a pointer, a clock, or a stored setting, and it does not start a microphone.
public enum PrompterRunBox {
    public enum Phase: Equatable, Sendable {
        case idle
        case running(mic: Int?)
    }

    public enum Step: Equatable, Sendable {
        case began(voiceFollow: Bool, session: Int)
        case ended
        case voiceChanged(on: Bool, session: Int)
        case micFailed(session: Int)
    }

    public enum Effect: Equatable, Sendable {
        case startMic(session: Int)
        case stopMic
    }

    public static func isRunning(_ phase: Phase) -> Bool {
        if case .running = phase { return true }
        return false
    }

    /// A level from `session` may move the meter and the scroll only while that microphone is the live one.
    public static func acceptsLevel(_ phase: Phase, from session: Int) -> Bool {
        if case .running(let mic) = phase { return mic == session }
        return false
    }

    public static func reduce(_ phase: Phase, _ step: Step) -> (Phase, [Effect]) {
        switch step {
        case .began(let voiceFollow, let session):
            guard case .idle = phase else { return (phase, []) }
            return voiceFollow ? (.running(mic: session), [.startMic(session: session)]) : (.running(mic: nil), [])

        case .ended:
            guard case .running(let mic) = phase else { return (.idle, []) }
            return (.idle, mic == nil ? [] : [.stopMic])

        case .voiceChanged(let on, let session):
            guard case .running(let mic) = phase else { return (phase, []) }
            switch (on, mic) {
            case (true, nil): return (.running(mic: session), [.startMic(session: session)])
            case (false, .some): return (.running(mic: nil), [.stopMic])
            default: return (phase, [])
            }

        case .micFailed(let session):
            guard case .running(let mic) = phase, mic == session else { return (phase, []) }
            return (.running(mic: nil), [.stopMic])
        }
    }
}
