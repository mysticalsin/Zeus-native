import Foundation

// The meeting card's own life, from the moment it shows to the moment it leaves. Pure: no AppKit, no clock,
// no Scribe controller. The app feeds what happened (a tap, the pointer, Scribe's phase, the time) and performs
// the effects. The rule it enforces: one tap always ends in either Scribe running, with "Starting..." shown at
// once, or a failure the person can read and act on. A tap is never dropped without a trace.

/// Why a tap on the card did not start Scribe. Each case says what to do next.
public enum ScribePopupFailure: Equatable, Sendable {
    /// macOS Microphone access is off for Zeus. The action opens System Settings.
    case microphoneOff
    /// Scribe is still ending or saving the previous meeting.
    case stillSaving
    /// Scribe tried and capture failed, with Scribe's own reason.
    case captureFailed(String)
    /// Scribe did not report a start in time.
    case noResponse

    public var message: String {
        switch self {
        case .microphoneOff:
            return "Microphone is off for Zeus, so Scribe can't hear the meeting."
        case .stillSaving:
            return "Scribe is still saving your last meeting. Try again in a moment."
        case .captureFailed(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Scribe couldn't start." : "Scribe couldn't start. \(trimmed)"
        case .noResponse:
            return "Scribe didn't start. Try again."
        }
    }

    public var actionTitle: String { self == .microphoneOff ? "Allow" : "Try again" }

    /// Short words for the diagnostics log.
    public var logReason: String {
        switch self {
        case .microphoneOff: return "microphone off"
        case .stillSaving: return "previous meeting still saving"
        case .captureFailed(let reason): return "capture failed: \(reason)"
        case .noResponse: return "no response"
        }
    }
}

public enum ScribePopupPhase: Equatable, Sendable {
    case hidden
    /// Asking: Record (or Start) and Not now.
    case shown
    /// Tapped: the card reads "Starting..." until Scribe reports.
    case starting
    /// Scribe is running. The card confirms briefly, then leaves.
    case started
    /// The tap could not start Scribe: the card says why and offers the fix.
    case failed(ScribePopupFailure)
    /// Left on its own (time ran out, or the meeting went away).
    case expired
    /// Not now.
    case dismissed

    public var isVisible: Bool {
        switch self {
        case .shown, .starting, .started, .failed: return true
        case .hidden, .expired, .dismissed: return false
        }
    }
}

public struct ScribePopupTiming: Equatable, Sendable {
    /// After the pointer leaves, the card stays at least this long, so it never vanishes under a moving hand.
    public var hoverGrace: TimeInterval
    /// Scribe must show a new session this soon after the tap, or the tap reports "didn't start".
    public var startTimeout: TimeInterval
    /// A session that is still "starting" (waiting on a macOS permission answer, say) gets this long.
    public var slowStartTimeout: TimeInterval
    /// How long "Scribe is recording" stays before the card leaves.
    public var confirmFor: TimeInterval
    /// How long a failure stays when the pointer is not over it.
    public var failureLifetime: TimeInterval

    public init(hoverGrace: TimeInterval = 4, startTimeout: TimeInterval = 5, slowStartTimeout: TimeInterval = 45,
                confirmFor: TimeInterval = 1.5, failureLifetime: TimeInterval = 60) {
        self.hoverGrace = hoverGrace
        self.startTimeout = startTimeout
        self.slowStartTimeout = slowStartTimeout
        self.confirmFor = confirmFor
        self.failureLifetime = failureLifetime
    }

    public static let standard = ScribePopupTiming()
}

public struct ScribePopupLifecycle: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// The card is shown for a meeting. `lifetime` nil: its owner decides when it leaves.
        case present(key: String, lifetime: TimeInterval?, now: TimeInterval)
        /// The primary button: Record, Start, or the failure's Allow / Try again.
        case click(now: TimeInterval, scribe: ScribePhase, microphoneBlocked: Bool)
        /// Scribe's phase, read after a start request and on every tick.
        case scribe(ScribePhase, now: TimeInterval)
        case pointer(inside: Bool, now: TimeInterval)
        case tick(now: TimeInterval)
        /// The meeting this card was about is over or no longer offered.
        case meetingGone(now: TimeInterval)
        /// Not now, or Close.
        case dismiss(now: TimeInterval)
    }

    public enum Effect: Equatable, Sendable {
        /// Start Scribe now. Emitted at most once per tap, never while a start is in flight.
        case requestStart
        case openMicrophoneSettings
        case hide
        /// The card ran out of time without an answer (the heads-up card counts that as Not now).
        case timedOut
    }

    public let timing: ScribePopupTiming
    public private(set) var phase: ScribePopupPhase = .hidden
    public private(set) var key: String?
    public private(set) var pointerInside = false
    /// The session this card's tap started, once Scribe shows it.
    public private(set) var session: ScribeSessionID?
    private var deadline: TimeInterval?
    private var startedAt: TimeInterval = 0
    /// Scribe's session at the moment of the tap. A phase from it is the previous meeting, never this start.
    private var previousSession: ScribeSessionID?

    public init(timing: ScribePopupTiming = .standard) {
        self.timing = timing
    }

    /// Starting, confirming, or showing a failure: the card's owner must not take it down for its own reasons.
    public var isBusy: Bool {
        switch phase {
        case .starting, .started, .failed: return true
        default: return false
        }
    }

    /// The app runs a timer only while this is true.
    public var needsTick: Bool { phase.isVisible }

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .present(let key, let lifetime, let now):
            // A tap in flight wins over a fresh prompt: never reset "Starting..." back to the question.
            if phase == .starting || phase == .started { return [] }
            self.key = key
            phase = .shown
            session = nil
            previousSession = nil
            deadline = lifetime.map { now + $0 }
            return []

        case .click(let now, let scribe, let blocked):
            return click(now: now, scribe: scribe, microphoneBlocked: blocked)

        case .scribe(let scribe, let now):
            return observe(scribe, now: now)

        case .pointer(let inside, let now):
            pointerInside = inside
            if !inside, let current = deadline, phase == .shown || isFailure {
                deadline = max(current, now + timing.hoverGrace)
            }
            return []

        case .tick(let now):
            return tick(now: now)

        case .meetingGone:
            guard phase == .shown else { return [] }
            phase = .expired
            deadline = nil
            return [.hide]

        case .dismiss:
            switch phase {
            case .shown, .failed, .started:
                phase = .dismissed
                deadline = nil
                return [.hide]
            default:
                // "Starting..." has no Not now; a stray close never cancels a start in flight.
                return []
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = phase { return true }
        return false
    }

    private mutating func click(now: TimeInterval, scribe: ScribePhase, microphoneBlocked: Bool) -> [Effect] {
        switch phase {
        case .starting, .started:
            // Double tap, or a tap after the start already went through: one start only.
            return []
        case .hidden, .dismissed:
            return []
        case .failed(.microphoneOff) where microphoneBlocked:
            return [.openMicrophoneSettings]
        case .shown, .expired, .failed:
            // An expired card can still take a tap that was already on its way: the person asked to record.
            break
        }
        if microphoneBlocked {
            fail(.microphoneOff, now: now)
            return []
        }
        switch scribe {
        case .starting(let id), .recording(let id, _):
            // Scribe already started (the automatic start, or a tap elsewhere won the race).
            succeed(id, now: now)
            return []
        case .ending, .processing:
            fail(.stillSaving, now: now)
            return []
        case .idle, .complete, .failed:
            phase = .starting
            startedAt = now
            deadline = nil
            session = nil
            previousSession = scribe.sessionID
            return [.requestStart]
        }
    }

    private mutating func observe(_ scribe: ScribePhase, now: TimeInterval) -> [Effect] {
        let waiting: Bool
        switch phase {
        case .starting: waiting = true
        case .failed(.noResponse): waiting = true
        default: waiting = false
        }
        guard waiting, let id = scribe.sessionID, id != previousSession else { return [] }
        switch scribe {
        case .starting:
            session = id
        case .recording, .ending, .processing, .complete:
            succeed(id, now: now)
        case .failed(_, let reason):
            session = id
            fail(.captureFailed(reason), now: now)
        case .idle:
            break
        }
        return []
    }

    private mutating func tick(now: TimeInterval) -> [Effect] {
        switch phase {
        case .shown:
            guard !pointerInside, let deadline, now >= deadline else { return [] }
            phase = .expired
            self.deadline = nil
            return [.hide, .timedOut]
        case .starting:
            let limit = session == nil ? timing.startTimeout : timing.slowStartTimeout
            if now - startedAt >= limit { fail(.noResponse, now: now) }
            return []
        case .started:
            guard let deadline, now >= deadline else { return [] }
            phase = .hidden
            self.deadline = nil
            return [.hide]
        case .failed:
            guard !pointerInside, let deadline, now >= deadline else { return [] }
            phase = .expired
            self.deadline = nil
            return [.hide]
        case .hidden, .expired, .dismissed:
            return []
        }
    }

    private mutating func succeed(_ id: ScribeSessionID, now: TimeInterval) {
        session = id
        phase = .started
        deadline = now + timing.confirmFor
    }

    private mutating func fail(_ failure: ScribePopupFailure, now: TimeInterval) {
        phase = .failed(failure)
        deadline = now + timing.failureLifetime
    }
}
