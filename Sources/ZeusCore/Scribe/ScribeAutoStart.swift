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

/// What Scribe itself is doing, from `ScribePhase`.
public enum ScribeActivity: Equatable, Sendable {
    case idle
    case starting
    case recording
    case ending
    case processing

    public init(_ phase: ScribePhase) {
        switch phase {
        case .idle, .complete, .failed: self = .idle
        case .starting: self = .starting
        case .recording: self = .recording
        case .ending: self = .ending
        case .processing: self = .processing
        }
    }
}

/// One meeting, identified so the same meeting never triggers twice.
public struct ScribeMeeting: Equatable, Sendable {
    /// The calendar slot id when a calendar event matched, else "call:<app>".
    public var key: String
    public var title: String
    public var callApp: ScribeCallApp
    public var slot: ScribeCalendarSlot?

    public init(key: String, title: String, callApp: ScribeCallApp, slot: ScribeCalendarSlot? = nil) {
        self.key = key
        self.title = title
        self.callApp = callApp
        self.slot = slot
    }

    /// The decision the existing call popup and `ScribeController` hints already understand.
    public var promptDecision: ScribePromptDecision {
        if let slot { return .upcoming(slot) }
        return .callDetected(callApp)
    }
}

/// Everything the detector knows at one moment. The microphone signal is "which call app holds the input",
/// read from CoreAudio process properties; Zeus's own process is never in `micApps`.
public struct ScribeMeetingEvidence: Equatable, Sendable {
    public var date: Date
    public var slots: [ScribeCalendarSlot]
    /// Known call apps (or a browser on a Meet tab) that hold the microphone now. Never Zeus.
    public var micApps: [ScribeCallApp]
    /// Known call apps running, or a browser showing a call tab, whether or not they use the microphone.
    public var presentApps: [ScribeCallApp]
    public var mode: ScribeAutoStartMode
    /// Microphone permission is already granted. The detector never asks for it.
    public var micPermissionGranted: Bool
    public var activity: ScribeActivity

    public init(date: Date, slots: [ScribeCalendarSlot] = [], micApps: [ScribeCallApp] = [],
                presentApps: [ScribeCallApp] = [], mode: ScribeAutoStartMode = .ask,
                micPermissionGranted: Bool = false, activity: ScribeActivity = .idle) {
        self.date = date
        self.slots = slots
        self.micApps = micApps
        self.presentApps = presentApps
        self.mode = mode
        self.micPermissionGranted = micPermissionGranted
        self.activity = activity
    }

    /// A meeting is under way when a call app holds the microphone, or when a calendar event with a call link is
    /// starting (a few minutes either side) and its call app is open. A calendar event alone, or an open app
    /// alone (Teams is always open), is not enough.
    public var candidate: ScribeMeeting? {
        let slot = ScribeMeetingStartPolicy.slot(in: slots, at: date)
        guard let app = micApps.first ?? (slot == nil ? nil : presentApps.first) else { return nil }
        if let slot {
            let title = slot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return ScribeMeeting(key: slot.id, title: title.isEmpty ? "Meeting" : title, callApp: app, slot: slot)
        }
        return ScribeMeeting(key: "call:\(ScribeCallDetection.displayName(app))",
                             title: ScribeCallPromptText.meetingTitle(for: .callDetected(app)) ?? "Meeting",
                             callApp: app)
    }
}

public enum ScribeMeetingStartPolicy {
    /// A calendar event counts from this long before it starts...
    public static let leadWindow: TimeInterval = ScribeCallPrompt.leadWindow
    /// ...until this long after.
    public static let lateWindow: TimeInterval = ScribeCallPrompt.lateWindow

    /// The slot with a call link whose start is closest to `date`, within the window and not yet over.
    public static func slot(in slots: [ScribeCalendarSlot], at date: Date) -> ScribeCalendarSlot? {
        slots.filter { slot in
            guard slot.hasCallLink else { return false }
            if let end = slot.end, date >= end { return false }
            let untilStart = slot.start.timeIntervalSince(date)
            return untilStart <= leadWindow && -untilStart <= lateWindow
        }.min { lhs, rhs in
            let l = abs(lhs.start.timeIntervalSince(date))
            let r = abs(rhs.start.timeIntervalSince(date))
            return l != r ? l < r : lhs.id < rhs.id
        }
    }
}

public struct ScribeAutoStartTiming: Equatable, Sendable {
    /// The same meeting must be seen again this long after it first appeared before anything is shown.
    public var debounce: TimeInterval
    /// "Ask me" leaves on its own after this long and counts as "Not now".
    public var askTimeout: TimeInterval
    /// "Start automatically" waits this long, with a Cancel button, before it starts.
    public var countdown: TimeInterval
    /// The call app must have released the microphone this long before an end is suggested.
    public var callEndedAfter: TimeInterval
    /// After an end is suggested, Scribe still recording after this long means the person kept it.
    public var endingGrace: TimeInterval
    /// After a start, Scribe may take this long to show as active before "not active" counts as stopped.
    public var startGrace: TimeInterval
    /// After a meeting is handled (started, declined, timed out) it cannot trigger again for this long, and
    /// then only once it has been gone for `rearmAfterAbsence`.
    public var cooldown: TimeInterval
    public var rearmAfterAbsence: TimeInterval

    public init(debounce: TimeInterval = 3, askTimeout: TimeInterval = 20, countdown: TimeInterval = 5,
                callEndedAfter: TimeInterval = 30, endingGrace: TimeInterval = 3, startGrace: TimeInterval = 10,
                cooldown: TimeInterval = 60, rearmAfterAbsence: TimeInterval = 30) {
        self.debounce = debounce
        self.askTimeout = askTimeout
        self.countdown = countdown
        self.callEndedAfter = callEndedAfter
        self.endingGrace = endingGrace
        self.startGrace = startGrace
        self.cooldown = cooldown
        self.rearmAfterAbsence = rearmAfterAbsence
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
    }

    public enum Effect: Equatable, Sendable {
        case showAsk(ScribeMeeting)
        case showCountdown(ScribeMeeting)
        case hideBanner
        case startRecording(ScribeMeeting)
        /// Open Scribe's end window, which stops and saves unless the person taps Keep recording.
        case requestEnd(ScribeMeeting)
    }

    public private(set) var state: ScribeAutoStartState = .idle
    public let timing: ScribeAutoStartTiming
    private var lastEvidence: ScribeMeetingEvidence?

    public init(timing: ScribeAutoStartTiming = .standard) {
        self.timing = timing
    }

    /// The banner's deadline, when one is showing.
    public var bannerDeadline: TimeInterval? {
        switch state {
        case .prompting(_, let deadline), .countingDown(_, let deadline): return deadline
        default: return nil
        }
    }

    /// The app runs a one second timer only while this is true.
    public var needsTick: Bool { bannerDeadline != nil }

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
                return [.hideBanner] + begin(meeting, now: now)
            default:
                return []
            }
        case .decline(let now):
            switch state {
            case .prompting(let meeting, _), .countingDown(let meeting, _):
                state = cooling(meeting.key, now: now)
                return [.hideBanner]
            default:
                return []
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
            if evidence.micApps.contains(recording.meeting.callApp) {
                recording.micReleasedAt = nil
                recording.sawMic = true
                state = .recording(recording)
                return []
            }
            guard recording.sawMic else { return [] }
            let released = recording.micReleasedAt ?? now
            recording.micReleasedAt = released
            if now - released >= timing.callEndedAfter, evidence.activity == .recording {
                state = .endingSuggested(meeting: recording.meeting, since: now)
                return [.requestEnd(recording.meeting)]
            }
            state = .recording(recording)
            return []

        case .endingSuggested(let meeting, let since):
            switch evidence.activity {
            case .idle:
                state = cooling(meeting.key, now: now)
                return [.hideBanner]
            case .recording where now - since >= timing.endingGrace:
                // Keep recording was chosen (or the end window never opened): wait for the call to come back.
                state = .recording(ScribeAutoStartRecording(meeting: meeting, since: now, micReleasedAt: nil, sawMic: false))
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
        if evidence.mode == .automatic, evidence.micPermissionGranted {
            state = .countingDown(meeting: meeting, deadline: now + timing.countdown)
            return [.showCountdown(meeting)]
        }
        // "Ask me", or "Start automatically" without Microphone permission already granted: Zeus never starts
        // capture from the detector without it, so it asks.
        state = .prompting(meeting: meeting, deadline: now + timing.askTimeout)
        return [.showAsk(meeting)]
    }

    private mutating func expire(now: TimeInterval) -> [Effect] {
        switch state {
        case .prompting(let meeting, let deadline) where now >= deadline:
            state = cooling(meeting.key, now: now)
            return [.hideBanner]
        case .countingDown(let meeting, let deadline) where now >= deadline:
            guard lastEvidence?.micPermissionGranted == true else {
                // Permission was withdrawn during the countdown: ask instead.
                state = .prompting(meeting: meeting, deadline: now + timing.askTimeout)
                return [.showAsk(meeting)]
            }
            return [.hideBanner] + begin(meeting, now: now)
        default:
            return []
        }
    }

    private mutating func begin(_ meeting: ScribeMeeting, now: TimeInterval) -> [Effect] {
        state = .recording(ScribeAutoStartRecording(meeting: meeting, since: now, micReleasedAt: nil, sawMic: false))
        return [.startRecording(meeting)]
    }

    private func cooling(_ key: String, now: TimeInterval) -> ScribeAutoStartState {
        .cooldown(ScribeAutoStartCooldown(key: key, until: now + timing.cooldown, absentSince: nil, gapSeen: false))
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
            return "Zeus starts taking notes 5 seconds after a meeting starts, and you can cancel. If Microphone is not allowed yet, it asks instead."
        }
    }

    public static let settingEndNote =
        "When the call ends, Zeus offers to stop and save the notes. You can keep recording."

    public static let askDetail = "Nothing is recorded until you tap Start."
    public static let countdownDetail = "Tap Cancel to keep Zeus from recording this meeting."
}
