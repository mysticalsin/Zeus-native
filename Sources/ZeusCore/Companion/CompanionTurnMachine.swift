import Foundation

/// Monotonic seconds for one companion turn. The machine compares these timestamps and never
/// reads the wall clock, the same rule as face presence (`ProcessInfo.systemUptime`): a wall-clock
/// change cannot make the deep spoken ceiling look exceeded.
public protocol CompanionClock: Sendable {
    func now() -> TimeInterval
}

public struct CompanionSystemClock: CompanionClock {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// A clock the caller moves. `now()` is monotonic. `jumpWall` is a discontinuity and does not move it.
public final class CompanionManualClock: CompanionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: TimeInterval
    private var wall: TimeInterval

    public init(now: TimeInterval) {
        instant = now
        wall = now
    }

    public func now() -> TimeInterval { lock.withLock { instant } }
    public func wallNow() -> TimeInterval { lock.withLock { wall } }

    public func advance(to time: TimeInterval) {
        lock.withLock { instant = time }
    }

    /// Moves the wall reading only. Monotonic `now()` stays put.
    public func jumpWall(by delta: TimeInterval) {
        lock.withLock { wall += delta }
    }
}

/// What the host does after a legal transition. A barge-in emits the three cancels in one step.
public enum CompanionTurnCommand: Equatable, Sendable {
    case startMic
    case stopMic
    case startCapture
    case cancelLLM
    case stopSpeech
    case cancelFlight
    case showListeningLamp
    case speakError(String)
}

public enum CompanionTurnEvent: Equatable, Sendable {
    case keyDown
    case keyUp
    case partialTranscript(String)
    case finalTranscript(String, instant: Bool)
    case firstToken
    case firstAudio
    case audioFinished
    /// A second hold while a turn is open.
    case bargeIn
    case captureFailed(String)
    case timeout
    case cancel
    case reset
}

public struct CompanionTurnRejection: Equatable, Sendable {
    public var phase: CompanionTurnPhase
    public var event: CompanionTurnEvent

    public init(phase: CompanionTurnPhase, event: CompanionTurnEvent) {
        self.phase = phase
        self.event = event
    }
}

public struct CompanionTurnStep: Equatable, Sendable {
    public var from: CompanionTurnPhase
    public var to: CompanionTurnPhase
    public var commands: [CompanionTurnCommand]

    public init(from: CompanionTurnPhase, to: CompanionTurnPhase, commands: [CompanionTurnCommand]) {
        self.from = from
        self.to = to
        self.commands = commands
    }
}

public struct CompanionTurnOutcome: Equatable, Sendable {
    public var steps: [CompanionTurnStep]
    public var commands: [CompanionTurnCommand]

    public init(steps: [CompanionTurnStep], commands: [CompanionTurnCommand]) {
        self.steps = steps
        self.commands = commands
    }
}

public enum CompanionTurnResponse: Equatable, Sendable {
    case accepted(CompanionTurnOutcome)
    case rejected(CompanionTurnRejection)
}

public enum CompanionLatencyMark: String, Hashable, Sendable {
    case keyDown
    case listening
    case keyUp
    case transcript
    case firstToken
    case firstAudio
    case audioFinished
}

/// Pure companion voice turn. Illegal events return a rejection and leave the phase alone.
/// The deep spoken ceiling is `FastTier.conversationWindowSeconds`. The host's first-byte
/// limit stays where it already lives; this machine does not keep a second copy. The host
/// sends `.timeout` when either limit fires.
public struct CompanionTurnMachine: Sendable {
    /// Spoken when the host reports that the answer did not arrive in time.
    public static let timeoutSpokenLine = "The answer took too long."
    /// The deep spoken window and the speaker quiet ceiling, already named on `FastTier`.
    public static var deepSpokenCeiling: TimeInterval { FastTier.conversationWindowSeconds }

    private static let bargeCancels: [CompanionTurnCommand] = [.stopSpeech, .cancelFlight, .cancelLLM]
    private static let beginListening: [CompanionTurnCommand] = [.showListeningLamp, .startMic, .startCapture]

    private let clock: any CompanionClock
    public private(set) var phase: CompanionTurnPhase
    public private(set) var partial = ""
    public private(set) var marks: [CompanionLatencyMark: TimeInterval] = [:]
    public private(set) var phaseEnteredAt: TimeInterval

    public init(clock: any CompanionClock = CompanionSystemClock()) {
        self.clock = clock
        phase = .idle
        phaseEnteredAt = clock.now()
    }

    public func elapsedInPhase() -> TimeInterval {
        max(0, clock.now() - phaseEnteredAt)
    }

    public func interval(_ start: CompanionLatencyMark, _ end: CompanionLatencyMark) -> TimeInterval? {
        guard let began = marks[start], let finished = marks[end] else { return nil }
        return finished - began
    }

    public var hotkeyToListening: TimeInterval? { interval(.keyDown, .listening) }
    public var keyUpToFirstAudio: TimeInterval? { interval(.keyUp, .firstAudio) }

    /// Compares key-up to first audio with the ceiling already stored on `VoiceLatencyTargets`.
    public func withinExistingFirstAudioCeiling(apiBrain: Bool, cloudVoice: Bool) -> Bool? {
        guard let seconds = keyUpToFirstAudio else { return nil }
        return seconds * 1_000 <= Double(VoiceLatencyTargets.targetMs(apiBrain: apiBrain, cloudVoice: cloudVoice))
    }

    /// True once thinking or speaking has lasted as long as `deepSpokenCeiling`.
    public func exceededDeepSpokenCeiling() -> Bool {
        switch phase {
        case .thinking, .speaking: return elapsedInPhase() >= Self.deepSpokenCeiling
        case .idle, .listening, .transcribing, .interrupted, .error: return false
        }
    }

    @discardableResult
    public mutating func send(_ event: CompanionTurnEvent) -> CompanionTurnResponse {
        let from = phase
        guard let decision = Self.transition(from: from, event: event) else {
            return .rejected(CompanionTurnRejection(phase: from, event: event))
        }
        let now = clock.now()
        phase = decision.phase
        if decision.phase != from { phaseEnteredAt = now }
        note(event, to: decision.phase)
        mark(event, to: decision.phase, at: now)
        let step = CompanionTurnStep(from: from, to: decision.phase, commands: decision.commands)
        return .accepted(CompanionTurnOutcome(steps: [step], commands: decision.commands))
    }

    private struct Decision {
        var phase: CompanionTurnPhase
        var commands: [CompanionTurnCommand]
    }

    private static func transition(from phase: CompanionTurnPhase, event: CompanionTurnEvent) -> Decision? {
        switch phase {
        case .idle:
            switch event {
            case .keyDown: return Decision(phase: .listening, commands: beginListening)
            case .reset: return Decision(phase: .idle, commands: [])
            default: return nil
            }
        case .listening:
            switch event {
            case .keyUp: return Decision(phase: .transcribing, commands: [.stopMic])
            case .partialTranscript: return Decision(phase: .listening, commands: [])
            case .captureFailed(let reason):
                let line = spoken(reason)
                return Decision(phase: .error(line), commands: [.stopMic, .speakError(line)])
            case .cancel, .reset: return Decision(phase: .idle, commands: [.stopMic])
            case .bargeIn: return Decision(phase: .interrupted, commands: bargeCancels + [.stopMic])
            default: return nil
            }
        case .transcribing:
            switch event {
            case .partialTranscript: return Decision(phase: .transcribing, commands: [])
            case .finalTranscript(let text, let instant):
                if blank(text) { return Decision(phase: .idle, commands: []) }
                return instant
                    ? Decision(phase: .speaking, commands: [])
                    : Decision(phase: .thinking, commands: [])
            case .captureFailed(let reason):
                let line = spoken(reason)
                return Decision(phase: .error(line), commands: [.speakError(line)])
            case .cancel, .reset: return Decision(phase: .idle, commands: [])
            case .bargeIn: return Decision(phase: .interrupted, commands: bargeCancels)
            default: return nil
            }
        case .thinking:
            switch event {
            case .firstToken: return Decision(phase: .thinking, commands: [])
            case .firstAudio: return Decision(phase: .speaking, commands: [])
            case .captureFailed(let reason):
                let line = spoken(reason)
                return Decision(phase: .error(line), commands: [.cancelLLM, .speakError(line)])
            case .timeout:
                return Decision(phase: .error(timeoutSpokenLine), commands: [.cancelLLM, .speakError(timeoutSpokenLine)])
            case .bargeIn, .cancel: return Decision(phase: .interrupted, commands: bargeCancels)
            case .reset: return Decision(phase: .idle, commands: bargeCancels)
            default: return nil
            }
        case .speaking:
            switch event {
            case .firstAudio: return Decision(phase: .speaking, commands: [])
            case .audioFinished: return Decision(phase: .idle, commands: [])
            case .timeout: return Decision(phase: .idle, commands: [.stopSpeech])
            case .bargeIn, .cancel: return Decision(phase: .interrupted, commands: bargeCancels)
            case .reset: return Decision(phase: .idle, commands: bargeCancels)
            default: return nil
            }
        case .interrupted:
            switch event {
            case .keyDown: return Decision(phase: .listening, commands: beginListening)
            case .bargeIn: return Decision(phase: .interrupted, commands: bargeCancels)
            case .cancel, .reset: return Decision(phase: .idle, commands: [])
            default: return nil
            }
        case .error:
            switch event {
            case .keyDown: return Decision(phase: .listening, commands: [.stopSpeech] + beginListening)
            case .audioFinished: return Decision(phase: .idle, commands: [])
            case .bargeIn: return Decision(phase: .interrupted, commands: bargeCancels)
            case .cancel, .reset: return Decision(phase: .idle, commands: [.stopSpeech])
            default: return nil
            }
        }
    }

    private static func spoken(_ raw: String) -> String { SpokenFailure.line(raw) }

    private static func blank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private mutating func note(_ event: CompanionTurnEvent, to: CompanionTurnPhase) {
        switch event {
        case .partialTranscript(let text):
            partial = text
        case .finalTranscript(let text, _):
            partial = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .keyDown, .reset:
            partial = ""
        default:
            if to == .idle || to == .interrupted { partial = "" }
        }
    }

    private mutating func mark(_ event: CompanionTurnEvent, to: CompanionTurnPhase, at now: TimeInterval) {
        switch event {
        case .keyDown where to == .listening:
            marks = [.keyDown: now, .listening: now]
        case .keyUp:
            marks[.keyUp] = now
        case .finalTranscript(let text, _):
            if !Self.blank(text) && (to == .thinking || to == .speaking) {
                marks[.transcript] = now
            }
        case .firstToken:
            if marks[.firstToken] == nil { marks[.firstToken] = now }
        case .firstAudio:
            if marks[.firstAudio] == nil { marks[.firstAudio] = now }
        case .audioFinished:
            marks[.audioFinished] = now
        case .reset:
            marks = [:]
        default:
            break
        }
    }
}
