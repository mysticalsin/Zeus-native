import Foundation

// Meeting-start policy for Scribe: one machine for the whole life of a meeting, from the sighting to the result.
// It asks, counts down, starts, confirms or says why capture did not begin, and when the call ends it suggests
// stopping. Pure: no calendar, process, audio or UI access, and no clock of its own. The app reads the signals
// (calendar, call apps, which process holds the microphone, Scribe's phase, microphone access), feeds them in as
// events, performs the `Effect`s this machine returns, and draws `card(now:)`, the only source of what is on
// screen. `nextWake(now:)` is the only source of when the app wakes.

/// Settings > Scribe > "When a meeting starts".
public enum ScribeAutoStartMode: String, CaseIterable, Sendable {
    case off
    case ask
    case automatic

    public static let settingID = "scribe.autoStart"
    public static let defaultMode: ScribeAutoStartMode = .ask
    public static var choices: [String] { allCases.map(\.title) }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .ask: return "Ask me"
        case .automatic: return "Start automatically"
        }
    }

    /// Anything unknown or missing is the safe default, "Ask me".
    public static func parse(_ text: String?) -> ScribeAutoStartMode {
        guard let text else { return defaultMode }
        return allCases.first { $0.title == text } ?? defaultMode
    }

    public static func current(defaults: UserDefaults = .standard) -> ScribeAutoStartMode {
        parse(FeatureSettings.string(settingID, default: defaultMode.title, defaults: defaults))
    }
}

public struct ScribeAutoStartTiming: Equatable, Sendable {
    /// The same meeting must be seen again this long after it first appeared before anything is shown.
    public var debounce: TimeInterval
    /// The meeting card leaves on its own after this long. Leaving is not a start.
    public var askTimeout: TimeInterval
    /// "Start automatically" waits this long, with a Cancel button, before it starts.
    public var countdown: TimeInterval
    /// The call app must have released the microphone (or its call window must have been gone) this long before an
    /// end is suggested. Short enough to feel prompt, long enough for a Zoom breakout room hop.
    public var callEndedAfter: TimeInterval
    /// A call the ledger remembers is forgotten once its app has not held the microphone for this long.
    public var rearmAfterAbsence: TimeInterval
    /// A card never leaves while the pointer is over it, and stays at least this long after the pointer leaves.
    public var hoverGrace: TimeInterval
    /// Scribe must show a new session this soon after a start, or the card says it did not start.
    public var startTimeout: TimeInterval
    /// A session that is still "starting" (waiting on a macOS permission answer, say) gets this long.
    public var slowStartTimeout: TimeInterval
    /// How long "Recording" stays on the card before it leaves.
    public var confirmFor: TimeInterval
    /// How long a failure stays when the pointer is not over it.
    public var failureLifetime: TimeInterval

    public init(debounce: TimeInterval = 3, askTimeout: TimeInterval = 10, countdown: TimeInterval = 5,
                callEndedAfter: TimeInterval = 8, rearmAfterAbsence: TimeInterval = 30, hoverGrace: TimeInterval = 4,
                startTimeout: TimeInterval = 5, slowStartTimeout: TimeInterval = 45, confirmFor: TimeInterval = 1.5,
                failureLifetime: TimeInterval = 60) {
        self.debounce = debounce
        self.askTimeout = askTimeout
        self.countdown = countdown
        self.callEndedAfter = callEndedAfter
        self.rearmAfterAbsence = rearmAfterAbsence
        self.hoverGrace = hoverGrace
        self.startTimeout = startTimeout
        self.slowStartTimeout = slowStartTimeout
        self.confirmFor = confirmFor
        self.failureLifetime = failureLifetime
    }

    public static let standard = ScribeAutoStartTiming()
}

/// What the app reads at the moment of each event that can start something: Scribe's phase, Microphone access,
/// and whether an automatic start may count down. The machine keeps no copy between events.
public struct ScribeStartContext: Equatable, Sendable {
    public var scribe: ScribePhase
    public var microphone: ScribeMicrophoneAccess
    public var automatic: ScribeAutoStartReadiness

    public init(scribe: ScribePhase = .idle, microphone: ScribeMicrophoneAccess = .allowed,
                automatic: ScribeAutoStartReadiness = .blocked(.notChosen)) {
        self.scribe = scribe
        self.microphone = microphone
        self.automatic = automatic
    }
}

/// Who asked for a start. A tap has no Cancel; an automatic start keeps one until its confirmation ends.
public enum ScribeStartOrigin: Equatable, Sendable {
    case tap
    case automatic
}

/// One request to start Scribe, from the moment it was made to the session it produced.
public struct ScribeStartAttempt: Equatable, Sendable {
    public var meeting: ScribeMeeting
    public var since: TimeInterval
    public var origin: ScribeStartOrigin
    /// Scribe's session when the request was made. A phase of that session is never this attempt's result.
    public var previousSession: ScribeSessionID?
    /// The session this attempt produced, once Scribe shows it.
    public var session: ScribeSessionID?

    public init(meeting: ScribeMeeting, since: TimeInterval, origin: ScribeStartOrigin,
                previousSession: ScribeSessionID?, session: ScribeSessionID?) {
        self.meeting = meeting
        self.since = since
        self.origin = origin
        self.previousSession = previousSession
        self.session = session
    }
}

public struct ScribeAutoStartRecording: Equatable, Sendable {
    public var meeting: ScribeMeeting
    public var since: TimeInterval
    /// When the call app let go of the microphone, while it still has not taken it back.
    public var micReleasedAt: TimeInterval?
    /// The call app held the microphone at some point. An end is only suggested after that, so a recording
    /// started from the calendar before anyone joined is not cut short.
    public var sawMic: Bool
    /// The call window was seen on screen at some point (so "gone" means it closed).
    public var sawWindow: Bool
    public var windowGoneAt: TimeInterval?
    /// "Next meeting" card: the meeting offered and when the card leaves.
    public var nextMeeting: ScribeMeeting?
    public var nextDeadline: TimeInterval?
    /// An end was suggested and the call has not come back since. One suggestion per quiet spell: the person's
    /// answer (Keep recording) is not read here, so nothing is suggested again until the call returns.
    public var endSuggested: Bool
    /// How this recording began. Only an automatic start can be discarded by Cancel.
    public var origin: ScribeStartOrigin
    /// The session this machine started or joined. Nil for a recording it only saw begin by hand.
    public var session: ScribeSessionID?
    /// The card says "Recording" until then, and an automatic start can still be cancelled. Nil afterwards.
    public var confirmUntil: TimeInterval?

    init(meeting: ScribeMeeting, since: TimeInterval, micReleasedAt: TimeInterval? = nil, sawMic: Bool = false,
         sawWindow: Bool = false, windowGoneAt: TimeInterval? = nil, nextMeeting: ScribeMeeting? = nil,
         nextDeadline: TimeInterval? = nil, endSuggested: Bool = false, origin: ScribeStartOrigin = .tap,
         session: ScribeSessionID? = nil, confirmUntil: TimeInterval? = nil) {
        self.meeting = meeting
        self.since = since
        self.micReleasedAt = micReleasedAt
        self.sawMic = sawMic
        self.sawWindow = sawWindow
        self.windowGoneAt = windowGoneAt
        self.nextMeeting = nextMeeting
        self.nextDeadline = nextDeadline
        self.endSuggested = endSuggested
        self.origin = origin
        self.session = session
        self.confirmUntil = confirmUntil
    }
}

public enum ScribeAutoStartState: Equatable, Sendable {
    case idle
    /// A calendar meeting starts within two minutes and nothing else is going on: the heads-up card is up until
    /// `deadline`. Leaving on its own is not an answer.
    case upcoming(meeting: ScribeMeeting, deadline: TimeInterval)
    /// A meeting was seen; waiting for the debounce before showing anything. A heads-up that was up when the
    /// meeting began stays on screen until `offerUntil`, so the card does not blink out during the check.
    case armed(meeting: ScribeMeeting, since: TimeInterval, offerUntil: TimeInterval? = nil)
    /// The offer is up. `blocked` is what stops an automatic start, so the card can say why.
    case prompting(meeting: ScribeMeeting, deadline: TimeInterval, blocked: ScribeAutoStartBlock?)
    /// "Start automatically": the countdown card is up with a Cancel button.
    case countingDown(meeting: ScribeMeeting, deadline: TimeInterval)
    /// Scribe is still ending or saving the last meeting. `startOwed` is a tap (or Switch) that starts the moment
    /// Scribe is free; without it the meeting is sighted again then.
    case held(meeting: ScribeMeeting, startOwed: Bool)
    /// Scribe was asked to start. The card says "Starting" until Scribe reports.
    case starting(ScribeStartAttempt)
    /// Capture began. The card confirms for a moment and leaves; the call is watched until Scribe is idle.
    case recording(ScribeAutoStartRecording)
    /// Capture did not begin. The card says why and offers the fix.
    case failed(attempt: ScribeStartAttempt, failure: ScribeStartFailure, deadline: TimeInterval)

    /// One plain line for the diagnostics log.
    public var logName: String {
        switch self {
        case .idle: return "idle"
        case .upcoming(let meeting, _): return "heads-up \(meeting.key)"
        case .armed(let meeting, _, _): return "armed \(meeting.key)"
        case .prompting(let meeting, _, _): return "offer \(meeting.key)"
        case .countingDown(let meeting, _): return "countdown \(meeting.key)"
        case .held(let meeting, _): return "waiting \(meeting.key)"
        case .starting(let attempt): return "starting \(attempt.meeting.key)"
        case .recording(let recording): return "recording \(recording.meeting.key)"
        case .failed(let attempt, let failure, _): return "failed \(attempt.meeting.key): \(failure.logReason)"
        }
    }
}

extension ScribeStartFailure {
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

extension ScribePhase {
    /// Short words for the diagnostics log.
    public var logName: String {
        switch self {
        case .idle: return "idle"
        case .starting: return "starting"
        case .recording: return "recording"
        case .ending: return "ending"
        case .processing: return "processing"
        case .complete: return "complete"
        case .failed(_, let reason): return "failed(\(reason))"
        }
    }
}

public struct ScribeAutoStartMachine: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case evidence(ScribeMeetingEvidence, now: TimeInterval)
        /// Scribe's phase, read after a start request and whenever it changes.
        case scribe(ScribePhase, now: TimeInterval)
        /// Deadlines only. Never advances a debounce or the call-ended timer: those need fresh evidence.
        case tick(now: TimeInterval, context: ScribeStartContext)
        /// The primary button of the card the person saw. The machine reads only the card's case and meeting, so
        /// a tap on a card that has since gone is still an answer (or ignored, by the late tap rules).
        case primary(on: ScribeMeetingCard, now: TimeInterval, context: ScribeStartContext)
        /// Cancel on the card the person saw.
        case cancel(on: ScribeMeetingCard, now: TimeInterval)
        /// The dismiss glyph on the card the person saw.
        case dismiss(on: ScribeMeetingCard, now: TimeInterval)
        /// The pointer entered or left the card. A card does not time out under the pointer.
        case pointer(inside: Bool, now: TimeInterval)
    }

    public enum Effect: Equatable, Sendable {
        /// Ask Scribe to start for this meeting. Emitted once per request; the app then sends `scribe` at once.
        case start(ScribeMeeting)
        /// Throw away the session an automatic start produced: nothing is saved.
        case abandonStart(ScribeSessionID)
        case openMicrophoneSettings
        /// The call looks over (microphone released, call window closed). Open Scribe's end window with no
        /// countdown. Nothing stops until a button is tapped.
        case suggestEnd(ScribeMeeting)
        /// The call came back: close the suggestion.
        case withdrawEnd
        /// Switch: end the recording that is running, at once and without a second question.
        case endNow
    }

    /// Wall time and machine time at the last evidence, to turn a slot's start into machine time.
    private struct ClockPoint: Equatable, Sendable {
        var date: Date
        var uptime: TimeInterval
    }

    public private(set) var state: ScribeAutoStartState = .idle
    public let timing: ScribeAutoStartTiming
    private var clock: ClockPoint?
    /// What was done about each meeting: asked, declined, started. The machine keeps no other memory of it.
    public private(set) var ledger = ScribeMeetingLedger()
    /// The pointer is over the card.
    public private(set) var pointerInside = false

    public init(timing: ScribeAutoStartTiming = .standard) {
        self.timing = timing
    }

    /// Nothing in hand and no clock, as at launch, but what was answered is kept: the choice going Off and back to
    /// Ask must not bring a dismissed meeting's card back.
    public mutating func reset() {
        state = .idle
        clock = nil
        pointerInside = false
    }

    // MARK: Views

    /// What is on screen. The card is a pure view of the state: nothing else decides it.
    public func card(now: TimeInterval) -> ScribeMeetingCard {
        switch state {
        case .idle:
            return .hidden
        case .armed(let meeting, _, let offerUntil):
            return offerUntil == nil ? .hidden : .offer(meeting, blocked: nil)
        case .upcoming(let meeting, _):
            return .offer(meeting, blocked: nil)
        case .prompting(let meeting, _, let blocked):
            return .offer(meeting, blocked: blocked)
        case .countingDown(let meeting, let deadline):
            return .countdown(meeting, seconds: ScribeMeetingCardText.seconds(deadline: deadline, now: now),
                              deadline: deadline, total: timing.countdown)
        case .held(let meeting, _):
            return .waiting(meeting)
        case .starting(let attempt):
            return .starting(attempt.meeting, cancellable: attempt.origin == .automatic)
        case .recording(let recording):
            if let until = recording.confirmUntil, now < until { return .recording(recording.meeting) }
            if let next = recording.nextMeeting { return .next(next) }
            return .hidden
        case .failed(let attempt, let failure, _):
            return .failed(attempt.meeting, failure)
        }
    }

    /// When the app must wake next: the earliest of the state's deadline, the next whole second of a countdown,
    /// the minute a time on the card changes, and one second ahead while the call looks over. Nil means nothing
    /// is scheduled. Never a moment that has already passed.
    public func nextWake(now: TimeInterval) -> TimeInterval? {
        var wakes: [TimeInterval] = []
        switch state {
        case .idle, .held:
            break
        case .armed(let meeting, _, let offerUntil):
            if let offerUntil {
                if !pointerInside { wakes.append(offerUntil) }
                wakes += minuteChange(of: meeting, now: now)
            }
        case .upcoming(let meeting, let deadline):
            if !pointerInside { wakes.append(deadline) }
            wakes += minuteChange(of: meeting, now: now)
        case .prompting(let meeting, let deadline, _):
            if !pointerInside { wakes.append(deadline) }
            wakes += minuteChange(of: meeting, now: now)
        case .countingDown(_, let deadline):
            wakes.append(deadline)
            let left = deadline - now
            if left > 0 { wakes.append(now + (left - (left.rounded(.up) - 1))) }
        case .starting(let attempt):
            wakes.append(attempt.since + (attempt.session == nil ? timing.startTimeout : timing.slowStartTimeout))
        case .recording(let recording):
            if let until = recording.confirmUntil { wakes.append(until) }
            if let next = recording.nextMeeting {
                if let deadline = recording.nextDeadline { wakes.append(deadline) }
                wakes += minuteChange(of: next, now: now)
            }
            if needsFreshEvidence { wakes.append(now + 1) }
        case .failed(_, _, let deadline):
            if !pointerInside { wakes.append(deadline) }
        }
        return wakes.filter { $0 > now }.min()
    }

    /// The call looks over or is about to: the app should read fresh signals each second, because a quiet spell
    /// only counts on evidence and a suggestion is withdrawn only when the call is seen coming back.
    public var needsFreshEvidence: Bool {
        guard case .recording(let recording) = state else { return false }
        return recording.micReleasedAt != nil || recording.windowGoneAt != nil
    }

    /// "in N min" turns to the next number, or to "now", at a whole minute before the meeting starts.
    private func minuteChange(of meeting: ScribeMeeting, now: TimeInterval) -> [TimeInterval] {
        guard let slot = meeting.slot, let clock else { return [] }
        let until = slot.start.timeIntervalSince(clock.date) - (now - clock.uptime)
        guard until > 0 else { return [] }
        let minutes = (until / 60).rounded(.up)
        return [now + (until - 60 * (minutes - 1))]
    }

    // MARK: Events

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        let effects: [Effect]
        switch event {
        case .evidence(let evidence, let now):
            clock = ClockPoint(date: evidence.date, uptime: now)
            ledger.observe(evidence, now: now, rearmAfterAbsence: timing.rearmAfterAbsence)
            effects = step(evidence, now: now)
        case .scribe(let phase, let now):
            effects = observe(phase, now: now)
        case .tick(let now, let context):
            effects = expire(now: now, context: context)
        case .primary(let card, let now, let context):
            effects = primary(card, now: now, context: context)
        case .cancel(let card, let now):
            effects = cancel(card, now: now)
        case .dismiss(let card, _):
            effects = dismiss(card)
        case .pointer(let inside, let now):
            pointer(inside: inside, now: now)
            effects = []
        }
        // A card that has gone takes the pointer with it: the next card is a fresh one.
        if !hasCard { pointerInside = false }
        return effects
    }

    private var hasCard: Bool {
        switch state {
        case .idle: return false
        case .armed(_, _, let offerUntil): return offerUntil != nil
        case .recording(let recording): return recording.confirmUntil != nil || recording.nextMeeting != nil
        default: return true
        }
    }

    private mutating func pointer(inside: Bool, now: TimeInterval) {
        pointerInside = inside
        guard !inside else { return }
        switch state {
        case .upcoming(let meeting, let deadline):
            state = .upcoming(meeting: meeting, deadline: max(deadline, now + timing.hoverGrace))
        case .armed(let meeting, let since, let offerUntil?):
            state = .armed(meeting: meeting, since: since, offerUntil: max(offerUntil, now + timing.hoverGrace))
        case .prompting(let meeting, let deadline, let blocked):
            state = .prompting(meeting: meeting, deadline: max(deadline, now + timing.hoverGrace), blocked: blocked)
        case .failed(let attempt, let failure, let deadline):
            state = .failed(attempt: attempt, failure: failure, deadline: max(deadline, now + timing.hoverGrace))
        default:
            break
        }
    }

    // MARK: Taps

    private mutating func primary(_ card: ScribeMeetingCard, now: TimeInterval, context: ScribeStartContext) -> [Effect] {
        switch card {
        case .offer(let seen, _):
            switch state {
            case .prompting(let meeting, _, _) where meeting.key == seen.key:
                return startRequest(meeting, origin: .tap, now: now, context: context)
            case .upcoming(let meeting, _) where meeting.key == seen.key:
                return startRequest(meeting, origin: .tap, now: now, context: context)
            case .armed(let meeting, _, _) where meeting.key == seen.key:
                // The call began while the heads-up was up: the meeting is the live one.
                return startRequest(meeting, origin: .tap, now: now, context: context)
            case .idle, .upcoming, .armed, .prompting:
                // The offer ended in the same instant (or another one replaced it): the person asked to record.
                return startRequest(seen, origin: .tap, now: now, context: context)
            case .countingDown, .held, .starting, .recording, .failed:
                // Something is already under way for a meeting: a second start would only cover it.
                return []
            }
        case .failed(let seen, _):
            guard case .failed(let attempt, let failure, _) = state, attempt.meeting.key == seen.key else { return [] }
            if failure == .microphoneOff, context.microphone == .denied { return [.openMicrophoneSettings] }
            return startRequest(attempt.meeting, origin: .tap, now: now, context: context)
        case .next(let seen):
            guard case .recording(let recording) = state, let next = recording.nextMeeting, next.key == seen.key else { return [] }
            // Switch: end this recording now, and start the next meeting once the notes of this one are saved.
            note(recording.meeting, .started)
            state = .held(meeting: next, startOwed: true)
            return [.endNow]
        case .hidden, .countdown, .waiting, .starting, .recording:
            return []
        }
    }

    private mutating func cancel(_ card: ScribeMeetingCard, now: TimeInterval) -> [Effect] {
        guard let key = card.meeting?.key else { return [] }
        switch state {
        case .countingDown(let meeting, _), .held(let meeting, _):
            guard meeting.key == key else { return [] }
            note(meeting, .declined)
            state = .idle
            return []
        case .starting(let attempt):
            guard attempt.meeting.key == key, attempt.origin == .automatic else { return [] }
            note(attempt.meeting, .declined)
            state = .idle
            return attempt.session.map { [.abandonStart($0)] } ?? []
        case .recording(let recording):
            guard recording.meeting.key == key, recording.origin == .automatic, let until = recording.confirmUntil,
                  now < until, let session = recording.session else { return [] }
            note(recording.meeting, .declined)
            state = .idle
            return [.abandonStart(session)]
        default:
            return []
        }
    }

    /// The dismiss glyph. A close on anything that is starting never cancels it.
    private mutating func dismiss(_ card: ScribeMeetingCard) -> [Effect] {
        switch card {
        case .offer(let seen, _):
            switch state {
            case .prompting(let meeting, _, _) where meeting.key == seen.key:
                note(meeting, .declined)
                state = .idle
            case .upcoming(let meeting, _) where meeting.key == seen.key:
                note(meeting, .declined)
                state = .idle
            case .idle:
                // The offer left in the same instant: the tap is still an answer.
                note(seen, .declined)
            case .armed(let meeting, _, _):
                note(seen, .declined)
                if meeting.key == seen.key { state = .idle }
            default:
                break
            }
        case .failed(let seen, _):
            if case .failed(let attempt, _, _) = state, attempt.meeting.key == seen.key {
                note(attempt.meeting, .declined)
                state = .idle
            }
        case .next(let seen):
            if case .recording(var recording) = state, recording.nextMeeting?.key == seen.key {
                note(seen, .declined)
                recording.nextMeeting = nil
                recording.nextDeadline = nil
                state = .recording(recording)
            }
        default:
            break
        }
        return []
    }

    // MARK: Starting

    /// The start rules, for a tap, a countdown that ended, a held start and Try again alike.
    private mutating func startRequest(_ meeting: ScribeMeeting, origin: ScribeStartOrigin, now: TimeInterval,
                                       context: ScribeStartContext) -> [Effect] {
        // Scribe is already on its way: join that session and start nothing. It is not ours to discard.
        switch context.scribe {
        case .starting(let id):
            state = .starting(ScribeStartAttempt(meeting: meeting, since: now, origin: .tap, previousSession: nil, session: id))
            return []
        case .recording(let id, _):
            confirm(meeting, origin: .tap, session: id, now: now)
            return []
        default:
            break
        }
        let attempt = ScribeStartAttempt(meeting: meeting, since: now, origin: origin,
                                         previousSession: context.scribe.sessionID, session: nil)
        guard context.microphone != .denied else {
            state = .failed(attempt: attempt, failure: .microphoneOff, deadline: now + timing.failureLifetime)
            return []
        }
        switch context.scribe {
        case .ending, .processing:
            state = .held(meeting: meeting, startOwed: origin == .tap)
            return []
        default:
            state = .starting(attempt)
            return [.start(meeting)]
        }
    }

    private mutating func confirm(_ meeting: ScribeMeeting, origin: ScribeStartOrigin, session: ScribeSessionID,
                                  now: TimeInterval) {
        state = .recording(ScribeAutoStartRecording(meeting: meeting, since: now, origin: origin, session: session,
                                                    confirmUntil: now + timing.confirmFor))
    }

    private mutating func fail(_ attempt: ScribeStartAttempt, _ failure: ScribeStartFailure, now: TimeInterval) {
        state = .failed(attempt: attempt, failure: failure, deadline: now + timing.failureLifetime)
    }

    /// Scribe's phase, read right after a start request and on every change.
    private mutating func observe(_ phase: ScribePhase, now: TimeInterval) -> [Effect] {
        switch state {
        case .starting(let attempt):
            follow(attempt, phase, now: now, late: false)
        case .failed(let attempt, .noResponse, _):
            // No response was said; a session that still arrives from this attempt is the late success.
            follow(attempt, phase, now: now, late: true)
        case .recording(var recording):
            settle(&recording, now: now)
            let sameSession = recording.session == nil || phase.sessionID == nil || phase.sessionID == recording.session
            if ScribeActivity(phase) == .idle, sameSession {
                note(recording.meeting, .started)
                state = .idle
            } else {
                state = .recording(recording)
            }
        default:
            break
        }
        return []
    }

    /// Reads a phase against one attempt. The session Scribe was on when the request was made is the previous
    /// meeting, never this attempt's result.
    private mutating func follow(_ attempt: ScribeStartAttempt, _ phase: ScribePhase, now: TimeInterval, late: Bool) {
        guard let id = phase.sessionID else { return }
        if id == attempt.previousSession {
            // The request was refused because the last meeting is still being saved: say so at once.
            if !late {
                switch phase {
                case .ending, .processing: fail(attempt, .stillSaving, now: now)
                default: break
                }
            }
            return
        }
        var attempt = attempt
        switch phase {
        case .starting:
            attempt.session = id
            if case .failed(_, let failure, let deadline) = state {
                state = .failed(attempt: attempt, failure: failure, deadline: deadline)
            } else {
                state = .starting(attempt)
            }
        case .recording:
            confirm(attempt.meeting, origin: attempt.origin, session: id, now: now)
        case .ending, .processing, .complete:
            // Capture was already over before the card could say it was recording: the card just leaves.
            note(attempt.meeting, .started)
            state = .idle
        case .failed(_, let reason):
            attempt.session = id
            fail(attempt, .captureFailed(reason), now: now)
        case .idle:
            break
        }
    }

    /// Ends the "Recording" confirmation once its time has passed. From then on it is a recording.
    private mutating func settle(_ recording: inout ScribeAutoStartRecording, now: TimeInterval) {
        guard let until = recording.confirmUntil, now >= until else { return }
        recording.confirmUntil = nil
        note(recording.meeting, .started)
    }

    // MARK: Deadlines

    private mutating func expire(now: TimeInterval, context: ScribeStartContext) -> [Effect] {
        switch state {
        case .upcoming(_, let deadline) where now >= deadline && !pointerInside:
            // Leaving on its own is not an answer: the ledger already says the heads-up was shown.
            state = .idle
            return []
        case .armed(let meeting, let since, let offerUntil?) where now >= offerUntil && !pointerInside:
            // The heads-up has had its time; the check on the call goes on without a card.
            state = .armed(meeting: meeting, since: since)
            return []
        case .prompting(let meeting, let deadline, _) where now >= deadline && !pointerInside:
            note(meeting, .asked)
            state = .idle
            return []
        case .countingDown(let meeting, let deadline) where now >= deadline:
            // A countdown never starts capture. The card asks, and only a tap records.
            return ask(meeting, now: now, blocked: context.automatic.block)
        case .held:
            return advanceHeld(now: now, context: context, evidence: nil)
        case .starting(let attempt):
            let limit = attempt.session == nil ? timing.startTimeout : timing.slowStartTimeout
            if now - attempt.since >= limit { fail(attempt, .noResponse, now: now) }
            return []
        case .failed(let attempt, _, let deadline) where now >= deadline && !pointerInside:
            // The failure left on its own: the meeting is handled and nothing retries by itself.
            note(attempt.meeting, .declined)
            state = .idle
            return []
        case .recording(var recording):
            settle(&recording, now: now)
            expireNextMeeting(&recording, now: now)
            state = .recording(recording)
            return []
        default:
            return []
        }
    }

    /// Takes the "next meeting" card down once its time is up. It counts as "Keep recording".
    private func expireNextMeeting(_ recording: inout ScribeAutoStartRecording, now: TimeInterval) {
        guard recording.nextMeeting != nil, let deadline = recording.nextDeadline, now >= deadline else { return }
        recording.nextMeeting = nil
        recording.nextDeadline = nil
    }

    // MARK: Steps

    private mutating func step(_ evidence: ScribeMeetingEvidence, now: TimeInterval) -> [Effect] {
        let context = evidence.context
        switch state {
        case .idle:
            guard evidence.mode != .off else { return [] }
            guard let meeting = evidence.candidate else {
                announce(evidence, now: now)
                return []
            }
            switch ScribeActivity(context.scribe) {
            case .starting, .recording:
                // A recording this machine did not start: this meeting is handled.
                note(meeting, .started)
                return []
            case .ending, .processing:
                guard offerable(meeting, evidence) else { return [] }
                state = .held(meeting: meeting, startOwed: false)
                return []
            case .idle:
                guard offerable(meeting, evidence) else { return [] }
                state = .armed(meeting: meeting, since: now)
                return armed(meeting, since: now, evidence: evidence, now: now)
            }

        case .upcoming(let meeting, let deadline):
            if evidence.mode == .off {
                state = .idle
                return []
            }
            switch ScribeActivity(context.scribe) {
            case .starting, .recording:
                // Recording began by hand: the card goes, and only a recording is an answer.
                note(meeting, .started)
                state = .idle
                return []
            case .idle, .ending, .processing:
                break
            }
            guard let candidate = evidence.candidate else { return expire(now: now, context: context) }
            if candidate.key == meeting.key {
                // The meeting began, or its call did: the card stays up through the check that follows.
                state = .armed(meeting: meeting, since: now, offerUntil: deadline)
            } else {
                // Something else is happening now: it replaces the heads-up and goes through the check on its own.
                state = .idle
            }
            return step(evidence, now: now)

        case .armed(let meeting, let since, let offerUntil):
            guard evidence.mode != .off, let current = evidence.candidate else {
                return backToHeadsUp(meeting, offerUntil: offerUntil, evidence, now: now)
            }
            switch ScribeActivity(context.scribe) {
            case .starting, .recording:
                note(current, .started)
                state = .idle
                return []
            case .ending, .processing:
                guard offerable(current, evidence) else { state = .idle; return [] }
                state = .held(meeting: current, startOwed: false)
                return []
            case .idle:
                break
            }
            guard offerable(current, evidence) else { state = .idle; return [] }
            let same = current.key == meeting.key
            let origin = same ? since : now
            state = .armed(meeting: current, since: origin, offerUntil: same ? offerUntil : nil)
            return armed(current, since: origin, evidence: evidence, now: now)

        case .prompting(let meeting, let deadline, _):
            if evidence.mode == .off {
                note(meeting, .asked)
                state = .idle
                return []
            }
            switch ScribeActivity(context.scribe) {
            case .starting, .recording:
                // Recording began by hand: the card goes, and only a recording is an answer.
                note(meeting, .started)
                state = .idle
                return []
            case .idle, .ending, .processing:
                break
            }
            state = .prompting(meeting: meeting, deadline: deadline, blocked: context.automatic.block)
            return expire(now: now, context: context)

        case .countingDown(let meeting, _):
            if evidence.mode == .off {
                note(meeting, .asked)
                state = .idle
                return []
            }
            switch ScribeActivity(context.scribe) {
            case .starting, .recording:
                note(meeting, .started)
                state = .idle
                return []
            case .idle, .ending, .processing:
                break
            }
            if !holdsCountdown(evidence) {
                // The choice, the readiness or the live call changed: nothing starts by itself, so ask instead.
                return ask(meeting, now: now, blocked: context.automatic.block)
            }
            return expire(now: now, context: context)

        case .held(_, let startOwed):
            if !startOwed, evidence.mode == .off {
                state = .idle
                return []
            }
            return advanceHeld(now: now, context: context, evidence: evidence)

        case .starting, .failed:
            // A start under way, or its failure, reacts only to Scribe, the time, taps and the pointer.
            return []

        case .recording(var recording):
            settle(&recording, now: now)
            switch ScribeActivity(context.scribe) {
            case .idle:
                note(recording.meeting, .started)
                state = .idle
                return []
            case .ending, .processing:
                state = .recording(recording)
                return []
            case .starting, .recording:
                break
            }
            expireNextMeeting(&recording, now: now)
            var effects: [Effect] = []
            if !recording.meeting.isLive, let live = evidence.candidate, live.isLive, live.key == recording.meeting.key {
                // The call began: the recording now follows the app that holds the microphone.
                recording.meeting = live
                note(live, .started)
            }
            let callApp = recording.meeting.callApp
            let micHeld = callApp.map { evidence.micApps.contains($0) } ?? false
            if micHeld {
                recording.micReleasedAt = nil
                recording.sawMic = true
            } else if recording.sawMic, recording.micReleasedAt == nil {
                recording.micReleasedAt = now
            }
            switch callApp.flatMap({ evidence.callWindows[$0] }) ?? .unknown {
            case .present:
                recording.sawWindow = true
                recording.windowGoneAt = nil
            case .gone:
                if recording.sawWindow, recording.windowGoneAt == nil { recording.windowGoneAt = now }
            case .unknown:
                break
            }
            let micEnded = recording.micReleasedAt.map { now - $0 >= timing.callEndedAfter } ?? false
            let windowEnded = recording.windowGoneAt.map { now - $0 >= timing.callEndedAfter } ?? false
            let callLooksOver = micEnded || windowEnded
            if callLooksOver, ScribeActivity(context.scribe) == .recording, !recording.endSuggested {
                // Advisory only: the recording keeps its state and Scribe keeps its phase.
                recording.endSuggested = true
                recording.nextMeeting = nil
                recording.nextDeadline = nil
                state = .recording(recording)
                return [.suggestEnd(recording.meeting)]
            }
            if !callLooksOver {
                // The call came back: the suggestion goes, and another one may follow a later quiet spell.
                if recording.endSuggested {
                    recording.endSuggested = false
                    effects.append(.withdrawEnd)
                }
                offerNextMeeting(&recording, evidence, now: now)
            }
            state = .recording(recording)
            return effects
        }
    }

    /// Scribe may have become free (or busy by hand) while a meeting was held. A tap that is owed starts then,
    /// once; a sighted meeting counts down or asks, as if seen now, and goes if its call is gone.
    private mutating func advanceHeld(now: TimeInterval, context: ScribeStartContext,
                                      evidence: ScribeMeetingEvidence?) -> [Effect] {
        guard case .held(let meeting, let startOwed) = state else { return [] }
        switch ScribeActivity(context.scribe) {
        case .ending, .processing:
            return []
        case .starting, .recording:
            if startOwed { return startRequest(meeting, origin: .tap, now: now, context: context) }
            note(meeting, .started)
            state = .idle
            return []
        case .idle:
            if startOwed { return startRequest(meeting, origin: .tap, now: now, context: context) }
            var current = meeting
            if let evidence {
                guard let candidate = evidence.candidate, candidate.key == meeting.key else { state = .idle; return [] }
                current = candidate
            }
            return ask(current, now: now, blocked: context.automatic.block)
        }
    }

    /// The heads-up: from `idle`, with no candidate and Scribe free, the closest meeting inside the lead window
    /// that nothing was done about yet. The ledger notes it at once, so it is shown once per meeting and an empty
    /// or failed calendar read cannot announce it again.
    private mutating func announce(_ evidence: ScribeMeetingEvidence, now: TimeInterval) {
        guard ScribeActivity(evidence.context.scribe) == .idle else { return }
        let marked = Set(evidence.slots.map(\.id).filter { ledger.mark(ofSlot: $0) != nil })
        guard let meeting = evidence.upcoming(excluding: marked) else { return }
        note(meeting, .headsUp)
        state = .upcoming(meeting: meeting, deadline: now + timing.askTimeout)
    }

    /// The call (or meeting) that armed a standing heads-up is gone before the check ended, a microphone blip
    /// say: the heads-up is back as it was, with the time it had left, and nothing counts down.
    private mutating func backToHeadsUp(_ armed: ScribeMeeting, offerUntil: TimeInterval?,
                                        _ evidence: ScribeMeetingEvidence, now: TimeInterval) -> [Effect] {
        guard evidence.mode != .off, let offerUntil, ScribeActivity(evidence.context.scribe) == .idle,
              let meeting = evidence.upcoming, meeting.key == armed.key else {
            state = .idle
            return []
        }
        state = .upcoming(meeting: meeting, deadline: offerUntil)
        return expire(now: now, context: evidence.context)
    }

    /// Debounced: shown only when the same meeting is still there once `debounce` has passed.
    private mutating func armed(_ meeting: ScribeMeeting, since: TimeInterval, evidence: ScribeMeetingEvidence,
                                now: TimeInterval) -> [Effect] {
        guard now - since >= timing.debounce else { return [] }
        if countsDown(meeting, evidence) {
            state = .countingDown(meeting: meeting, deadline: now + timing.countdown)
            return []
        }
        return ask(meeting, now: now, blocked: evidence.context.automatic.block)
    }

    /// A meeting card never starts capture by itself, even when Start automatically is chosen and ready.
    /// Recording begins only from a tap.
    private func countsDown(_: ScribeMeeting, _: ScribeMeetingEvidence) -> Bool {
        false
    }

    /// What must still be true on every evidence while the countdown runs, and at its end.
    private func holdsCountdown(_ evidence: ScribeMeetingEvidence) -> Bool {
        evidence.mode == .automatic && evidence.context.automatic.isReady && evidence.candidate?.isLive == true
    }

    /// An answered meeting is never shown again. Whatever the ledger knows about it, even a question that timed
    /// out, is written onto the meeting itself, so a call's mark moves to its calendar slot and outlives the call's
    /// entry. A meeting whose question timed out is shown again only when it would count down.
    private mutating func offerable(_ meeting: ScribeMeeting, _ evidence: ScribeMeetingEvidence) -> Bool {
        guard let mark = ledger.mark(of: meeting) else { return true }
        note(meeting, mark)
        if mark.isAnswered { return false }
        return mark != .asked || countsDown(meeting, evidence)
    }

    private mutating func note(_ meeting: ScribeMeeting, _ mark: ScribeMeetingLedger.Mark) {
        ledger.note(meeting, mark, date: clock?.date ?? .distantPast)
    }

    /// The meeting card. Start automatically asks too: capture begins only when the person taps.
    private mutating func ask(_ meeting: ScribeMeeting, now: TimeInterval, blocked: ScribeAutoStartBlock?) -> [Effect] {
        state = .prompting(meeting: meeting, deadline: now + timing.askTimeout, blocked: blocked)
        return []
    }

    /// While recording, another calendar meeting with a call link is about to start: offer it once. The ledger
    /// remembers the offer, so it is not repeated and the meeting is still new when this recording ends.
    private mutating func offerNextMeeting(_ recording: inout ScribeAutoStartRecording, _ evidence: ScribeMeetingEvidence,
                                           now: TimeInterval) {
        guard recording.nextMeeting == nil, evidence.mode != .off else { return }
        let known = evidence.slots.map(\.id).filter { ledger.mark(ofSlot: $0) != nil }
        let excluded = Set(known).union([recording.meeting.key])
        guard let slot = ScribeMeetingStartPolicy.nextSlot(in: evidence.slots, excluding: excluded, at: evidence.date) else { return }
        let next = ScribeMeeting(key: slot.id, title: ScribeMeetingEvidence.title(of: slot),
                                 callApp: slot.callApp ?? evidence.presentApps.first ?? recording.meeting.callApp, slot: slot)
        note(next, .headsUp)
        recording.nextMeeting = next
        recording.nextDeadline = now + timing.askTimeout
    }
}
