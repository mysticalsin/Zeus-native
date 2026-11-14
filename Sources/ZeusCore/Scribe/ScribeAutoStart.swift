import Foundation

// Meeting-start policy for Scribe: when a meeting begins, ask, start on its own, or do nothing; and when the
// call ends, suggest stopping. Pure: no calendar, process, audio or UI access. The app reads the signals
// (calendar, call apps, which process holds the microphone), feeds them in as `ScribeMeetingEvidence`, and
// performs the `Effect`s this machine returns.

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

/// The one-time agreement that lets "Start automatically" start without asking. Stored as a timestamp.
public enum ScribeAutoStartConsent {
    public static let key = "scribe.autoStart.consentAt"

    public static func isGiven(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) is Double
    }

    public static func consentDate(defaults: UserDefaults = .standard) -> Date? {
        (defaults.object(forKey: key) as? Double).map(Date.init(timeIntervalSince1970:))
    }

    public static func record(at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }
}

public struct ScribeAutoStartTiming: Equatable, Sendable {
    /// The same meeting must be seen again this long after it first appeared before anything is shown.
    public var debounce: TimeInterval
    /// "Ask me" leaves on its own after this long and counts as "Not now".
    public var askTimeout: TimeInterval
    /// "Start automatically" waits this long, with a Cancel button, before it starts.
    public var countdown: TimeInterval
    /// The call app must have released the microphone (or its call window must have been gone) this long before an
    /// end is suggested. Short enough to feel prompt, long enough for a Zoom breakout room hop.
    public var callEndedAfter: TimeInterval
    /// After an end is suggested, Scribe still recording after this long means the person kept it.
    public var endingGrace: TimeInterval
    /// After a start, Scribe may take this long to show as active before "not active" counts as stopped.
    public var startGrace: TimeInterval
    /// After a meeting is handled (started, declined, timed out) it cannot trigger again for this long, and
    /// then only once it has been gone for `rearmAfterAbsence`.
    public var cooldown: TimeInterval
    public var rearmAfterAbsence: TimeInterval
    /// "Ask me" never leaves while the pointer is over it, and stays at least this long after the pointer leaves.
    public var hoverGrace: TimeInterval

    public init(debounce: TimeInterval = 3, askTimeout: TimeInterval = 20, countdown: TimeInterval = 5,
                callEndedAfter: TimeInterval = 8, endingGrace: TimeInterval = 3, startGrace: TimeInterval = 10,
                cooldown: TimeInterval = 60, rearmAfterAbsence: TimeInterval = 30, hoverGrace: TimeInterval = 4) {
        self.debounce = debounce
        self.askTimeout = askTimeout
        self.countdown = countdown
        self.callEndedAfter = callEndedAfter
        self.endingGrace = endingGrace
        self.startGrace = startGrace
        self.cooldown = cooldown
        self.rearmAfterAbsence = rearmAfterAbsence
        self.hoverGrace = hoverGrace
    }

    public static let standard = ScribeAutoStartTiming()
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
    /// Calendar events already offered during this recording, so each is offered once.
    public var nextOffered: Set<String>

    init(meeting: ScribeMeeting, since: TimeInterval, micReleasedAt: TimeInterval? = nil, sawMic: Bool = false,
         sawWindow: Bool = false, windowGoneAt: TimeInterval? = nil, nextMeeting: ScribeMeeting? = nil,
         nextDeadline: TimeInterval? = nil, nextOffered: Set<String> = []) {
        self.meeting = meeting
        self.since = since
        self.micReleasedAt = micReleasedAt
        self.sawMic = sawMic
        self.sawWindow = sawWindow
        self.windowGoneAt = windowGoneAt
        self.nextMeeting = nextMeeting
        self.nextDeadline = nextDeadline
        self.nextOffered = nextOffered
    }
}

public struct ScribeAutoStartCooldown: Equatable, Sendable {
    public var key: String
    public var until: TimeInterval
    /// Since when this meeting has not been seen (a different meeting counts as not seen).
    public var absentSince: TimeInterval?
    /// The meeting was gone long enough that it coming back is a new meeting.
    public var gapSeen: Bool
}

public enum ScribeAutoStartState: Equatable, Sendable {
    case idle
    /// A meeting was seen; waiting for the debounce before showing anything.
    case armed(meeting: ScribeMeeting, since: TimeInterval)
    /// "Ask me": the banner is up.
    case prompting(meeting: ScribeMeeting, deadline: TimeInterval)
    /// "Start automatically": the banner is up with a Cancel button.
    case countingDown(meeting: ScribeMeeting, deadline: TimeInterval)
    case recording(ScribeAutoStartRecording)
    /// The call ended; Scribe's own end window (with Keep recording) is up.
    case endingSuggested(meeting: ScribeMeeting, since: TimeInterval)
    case cooldown(ScribeAutoStartCooldown)
}

public struct ScribeAutoStartMachine: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case evidence(ScribeMeetingEvidence, now: TimeInterval)
        /// Deadlines only. Never advances a debounce or the call-ended timer: those need fresh evidence.
        case tick(now: TimeInterval)
        /// Start was tapped (also valid during the countdown: start now).
        case accept(now: TimeInterval)
        /// Not now, or Cancel.
        case decline(now: TimeInterval)
        /// The pointer entered or left the banner. "Ask me" does not time out under the pointer.
        case pointer(inside: Bool, now: TimeInterval)
        /// The person tapped Start on the card showing `meeting`, but the card's question is no longer pending
        /// (it timed out or was replaced at the same moment). An explicit tap still starts, unless Scribe is
        /// already recording a meeting.
        case startNow(ScribeMeeting, now: TimeInterval)
    }

    public enum Effect: Equatable, Sendable {
        case showAsk(ScribeMeeting)
        case showCountdown(ScribeMeeting)
        /// The first time "Start automatically" would fire: ask once, and remember the answer.
        case showConsentAsk(ScribeMeeting)
        /// Store the consent timestamp (`ScribeAutoStartConsent.record`).
        case recordConsent
        /// Another meeting is starting while this one records.
        case showNextMeeting(ScribeMeeting)
        case hideBanner
        case startRecording(ScribeMeeting)
        /// Open Scribe's end window, which stops and saves unless the person taps Keep recording.
        case requestEnd(ScribeMeeting)
    }

    public private(set) var state: ScribeAutoStartState = .idle
    public let timing: ScribeAutoStartTiming
    private var lastEvidence: ScribeMeetingEvidence?
    /// The person chose "Switch" on the next-meeting card: the next meeting may trigger without the cooldown.
    private var switching = false
    /// The pointer is over the banner.
    public private(set) var pointerInside = false

    public init(timing: ScribeAutoStartTiming = .standard) {
        self.timing = timing
    }

    /// The banner's deadline, when one is showing.
    public var bannerDeadline: TimeInterval? {
        switch state {
        case .prompting(_, let deadline), .countingDown(_, let deadline): return deadline
        case .recording(let recording): return recording.nextMeeting == nil ? nil : recording.nextDeadline
        default: return nil
        }
    }

    /// The call looks over and the end timer is running: the app should read fresh signals each second, because
    /// the timer only advances on evidence.
    public var needsFreshEvidence: Bool {
        guard case .recording(let recording) = state else { return false }
        return recording.micReleasedAt != nil || recording.windowGoneAt != nil
    }

    /// The app runs a one second timer only while this is true.
    public var needsTick: Bool { bannerDeadline != nil || needsFreshEvidence }

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .evidence(let evidence, let now):
            lastEvidence = evidence
            return step(evidence, now: now)
        case .tick(let now):
            return expire(now: now)
        case .accept(let now):
            switch state {
            case .prompting(let meeting, _), .countingDown(let meeting, _):
                var effects: [Effect] = [.hideBanner]
                if let last = lastEvidence, last.mode == .automatic, last.micPermissionGranted, !last.autoConsentGiven {
                    effects.append(.recordConsent)
                }
                return effects + begin(meeting, now: now)
            case .recording(let recording):
                guard recording.nextMeeting != nil else { return [] }
                // Switch: end this recording (the end window can still be cancelled) and let the next meeting start.
                switching = true
                state = .endingSuggested(meeting: recording.meeting, since: now)
                return [.hideBanner, .requestEnd(recording.meeting)]
            default:
                return []
            }
        case .decline(let now):
            switch state {
            case .prompting(let meeting, _), .countingDown(let meeting, _):
                state = cooling(meeting.key, now: now)
                return [.hideBanner]
            case .recording(var recording):
                guard recording.nextMeeting != nil else { return [] }
                recording.nextMeeting = nil
                recording.nextDeadline = nil
                state = .recording(recording)
                return [.hideBanner]
            default:
                return []
            }
        case .pointer(let inside, let now):
            pointerInside = inside
            if !inside, case .prompting(let meeting, let deadline) = state {
                state = .prompting(meeting: meeting, deadline: max(deadline, now + timing.hoverGrace))
            }
            return []
        case .startNow(let meeting, let now):
            switch state {
            case .prompting, .countingDown:
                return handle(.accept(now: now))
            case .recording, .endingSuggested:
                return []
            case .idle, .armed, .cooldown:
                return [.hideBanner] + begin(meeting, now: now)
            }
        }
    }

    // MARK: Steps

    private mutating func step(_ evidence: ScribeMeetingEvidence, now: TimeInterval) -> [Effect] {
        switch state {
        case .idle:
            guard evidence.mode != .off, let meeting = evidence.candidate else { return [] }
            if evidence.activity != .idle {
                // The person is already recording by hand: this meeting is handled.
                state = cooling(meeting.key, now: now)
                return []
            }
            state = .armed(meeting: meeting, since: now)
            return armed(meeting, since: now, evidence: evidence, now: now)

        case .armed(let meeting, let since):
            guard evidence.mode != .off else { state = .idle; return [] }
            guard let current = evidence.candidate else { state = .idle; return [] }
            if evidence.activity != .idle { state = cooling(current.key, now: now); return [] }
            if current.key != meeting.key {
                state = .armed(meeting: current, since: now)
                return armed(current, since: now, evidence: evidence, now: now)
            }
            state = .armed(meeting: current, since: since)
            return armed(current, since: since, evidence: evidence, now: now)

        case .prompting(let meeting, _), .countingDown(let meeting, _):
            if evidence.mode == .off || evidence.activity != .idle {
                state = cooling(meeting.key, now: now)
                return [.hideBanner]
            }
            return expire(now: now)

        case .recording(var recording):
            switch evidence.activity {
            case .idle:
                guard now - recording.since >= timing.startGrace else { return [] }
                state = cooling(recording.meeting.key, now: now)
                return [.hideBanner]
            case .ending, .processing:
                return []
            case .starting, .recording:
                break
            }
            var effects = expireNextMeeting(&recording, now: now)
            let micHeld = evidence.micApps.contains(recording.meeting.callApp)
            if micHeld {
                recording.micReleasedAt = nil
                recording.sawMic = true
            } else if recording.sawMic, recording.micReleasedAt == nil {
                recording.micReleasedAt = now
            }
            switch evidence.callWindows[recording.meeting.callApp] ?? .unknown {
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
            if (micEnded || windowEnded), evidence.activity == .recording {
                if recording.nextMeeting != nil { effects.append(.hideBanner) }
                state = .endingSuggested(meeting: recording.meeting, since: now)
                return effects + [.requestEnd(recording.meeting)]
            }
            effects += offerNextMeeting(&recording, evidence, now: now)
            state = .recording(recording)
            return effects

        case .endingSuggested(let meeting, let since):
            switch evidence.activity {
            case .idle:
                state = cooling(meeting.key, now: now)
                switching = false
                return [.hideBanner]
            case .recording where now - since >= timing.endingGrace:
                // Keep recording was chosen (or the end window never opened): wait for the call to come back.
                switching = false
                state = .recording(ScribeAutoStartRecording(meeting: meeting, since: now))
                return []
            default:
                return []
            }

        case .cooldown(var cooldown):
            let candidate = evidence.candidate
            let absent = candidate == nil || candidate?.key != cooldown.key
            if absent {
                let since = cooldown.absentSince ?? now
                cooldown.absentSince = since
                if now - since >= timing.rearmAfterAbsence { cooldown.gapSeen = true }
            } else {
                cooldown.absentSince = nil
            }
            let differentMeeting = candidate != nil && candidate?.key != cooldown.key
            if now >= cooldown.until, cooldown.gapSeen || differentMeeting {
                state = .idle
                return step(evidence, now: now)
            }
            state = .cooldown(cooldown)
            return []
        }
    }

    /// Debounced: shown only when the same meeting is still there once `debounce` has passed.
    private mutating func armed(_ meeting: ScribeMeeting, since: TimeInterval, evidence: ScribeMeetingEvidence,
                                now: TimeInterval) -> [Effect] {
        guard now - since >= timing.debounce else { return [] }
        if evidence.mode == .automatic, evidence.micPermissionGranted, evidence.autoConsentGiven {
            state = .countingDown(meeting: meeting, deadline: now + timing.countdown)
            return [.showCountdown(meeting)]
        }
        return ask(meeting, evidence, now: now)
    }

    /// "Ask me", or "Start automatically" without Microphone permission already granted or without the one-time
    /// consent: Zeus never starts capture from the detector without both, so it asks. The first automatic start asks
    /// in words that also record the consent.
    private mutating func ask(_ meeting: ScribeMeeting, _ evidence: ScribeMeetingEvidence?, now: TimeInterval) -> [Effect] {
        // A fresh card: an old "pointer inside" from a card that was taken down must not hold this one.
        pointerInside = false
        state = .prompting(meeting: meeting, deadline: now + timing.askTimeout)
        if let evidence, evidence.mode == .automatic, evidence.micPermissionGranted, !evidence.autoConsentGiven {
            return [.showConsentAsk(meeting)]
        }
        return [.showAsk(meeting)]
    }

    private mutating func expire(now: TimeInterval) -> [Effect] {
        switch state {
        case .prompting(let meeting, let deadline) where now >= deadline && !pointerInside:
            state = cooling(meeting.key, now: now)
            return [.hideBanner]
        case .countingDown(let meeting, let deadline) where now >= deadline:
            guard lastEvidence?.micPermissionGranted == true, lastEvidence?.autoConsentGiven == true else {
                // Permission (or consent) was withdrawn during the countdown: ask instead.
                return ask(meeting, lastEvidence, now: now)
            }
            return [.hideBanner] + begin(meeting, now: now)
        case .recording(var recording):
            let effects = expireNextMeeting(&recording, now: now)
            state = .recording(recording)
            return effects
        default:
            return []
        }
    }

    private mutating func begin(_ meeting: ScribeMeeting, now: TimeInterval) -> [Effect] {
        state = .recording(ScribeAutoStartRecording(meeting: meeting, since: now))
        return [.startRecording(meeting)]
    }

    private func cooling(_ key: String, now: TimeInterval) -> ScribeAutoStartState {
        let until = switching ? now : now + timing.cooldown
        return .cooldown(ScribeAutoStartCooldown(key: key, until: until, absentSince: nil, gapSeen: false))
    }

    /// Takes the "next meeting" card down once its time is up. It counts as "Keep recording".
    private func expireNextMeeting(_ recording: inout ScribeAutoStartRecording, now: TimeInterval) -> [Effect] {
        guard recording.nextMeeting != nil, let deadline = recording.nextDeadline, now >= deadline else { return [] }
        recording.nextMeeting = nil
        recording.nextDeadline = nil
        return [.hideBanner]
    }

    /// While recording, another calendar meeting with a call link is about to start: offer it once.
    private func offerNextMeeting(_ recording: inout ScribeAutoStartRecording, _ evidence: ScribeMeetingEvidence,
                                  now: TimeInterval) -> [Effect] {
        guard recording.nextMeeting == nil, evidence.mode != .off else { return [] }
        let excluded = recording.nextOffered.union([recording.meeting.key])
        guard let slot = ScribeMeetingStartPolicy.nextSlot(in: evidence.slots, excluding: excluded, at: evidence.date) else { return [] }
        let title = slot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = ScribeMeeting(key: slot.id, title: title.isEmpty ? "Meeting" : title,
                                 callApp: evidence.presentApps.first ?? recording.meeting.callApp, slot: slot)
        recording.nextMeeting = next
        recording.nextDeadline = now + timing.askTimeout
        recording.nextOffered.insert(slot.id)
        return [.showNextMeeting(next)]
    }
}

/// Banner wording. Plain words, no dashes.
public enum ScribeAutoStartText {
    public static func askHeadline(_ meeting: ScribeMeeting) -> String {
        "Meeting started: \(meeting.title). Take notes?"
    }

    public static func countdownHeadline(_ meeting: ScribeMeeting, seconds: Int) -> String {
        "Meeting started: \(meeting.title). Taking notes in \(max(0, seconds))."
    }

    /// Under the Settings choice.
    public static func settingNote(_ mode: ScribeAutoStartMode) -> String {
        switch mode {
        case .off:
            return "Zeus never offers to take notes when a meeting starts."
        case .ask:
            return "Zeus asks when a call or a calendar meeting starts. Nothing is recorded until you tap Start."
        case .automatic:
            return "Zeus starts taking notes 5 seconds after a meeting starts, and you can cancel. It asks once the first time, and asks every time while Microphone is not allowed."
        }
    }

    public static let settingEndNote =
        "When the call ends, Zeus offers to stop and save the notes. You can keep recording. If another meeting starts while you record, Zeus asks before switching."

    public static func nextMeetingHeadline(_ meeting: ScribeMeeting) -> String {
        "Next meeting: \(meeting.title) is starting. Switch notes to it?"
    }

    public static let nextMeetingDetail = "Switching stops this recording and saves it first. Keep recording leaves it running."
    public static let consentDetail =
        "You chose Start automatically. Tap Start and allow, and Zeus will start by itself from now on, after a 5 second countdown you can cancel."

    public static let askDetail = "Nothing is recorded until you tap Start."
    public static let countdownDetail = "Tap Cancel to keep Zeus from recording this meeting."
}
