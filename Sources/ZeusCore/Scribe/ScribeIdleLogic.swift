import Foundation

/// Pure logic for the redesigned Scribe page: the "Up next" card, the source chips, the "Now speaking" pill and
/// the slow decorative wave. The views only draw what these return.

public struct ScribeUpNextMeeting: Equatable, Sendable {
    public var slot: ScribeCalendarSlot
    /// The call app of the invite's link, when it has one.
    public var app: ScribeCallApp?

    public init(slot: ScribeCalendarSlot, app: ScribeCallApp?) {
        self.slot = slot
        self.app = app
    }
}

public enum ScribeUpNext {
    /// A meeting still counts as "up next" this long after it started when it has no end time.
    public static let openEndedGrace: TimeInterval = 10 * 60

    /// The meeting to offer: the earliest one that has not ended. Nothing for a finished one.
    public static func pick(_ meetings: [ScribeUpNextMeeting], now: Date) -> ScribeUpNextMeeting? {
        let open = meetings.filter { meeting in
            if let end = meeting.slot.end { return end > now }
            return meeting.slot.start.addingTimeInterval(openEndedGrace) > now
        }
        return open.min { lhs, rhs in
            lhs.slot.start != rhs.slot.start ? lhs.slot.start < rhs.slot.start : lhs.slot.id < rhs.slot.id
        }
    }

    /// "in 4 min", "in 1 h 15 min", "starting now", "started 3 min ago".
    public static func startsIn(_ start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)
        if abs(delta) < 60 { return "starting now" }
        if delta < 0 {
            let minutes = Int((-delta / 60).rounded(.down))
            return minutes < 60 ? "started \(minutes) min ago" : "started \(minutes / 60) h ago"
        }
        let minutes = Int((delta / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
    }

    /// The call app behind a meeting link; nil without a link.
    public static func callApp(link: URL?) -> ScribeCallApp? {
        guard let host = link?.host?.lowercased() else { return nil }
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if matches("teams.microsoft.com") || matches("teams.live.com") { return .teams }
        if matches("zoom.us") { return .zoom }
        if matches("meet.google.com") { return .meet }
        return .other(host)
    }

    /// The name the card shows beside the logo; nil when there is no link.
    public static func appName(_ app: ScribeCallApp?) -> String? {
        switch app {
        case .teams: return "Teams"
        case .zoom: return "Zoom"
        case .meet: return "Google Meet"
        case .other: return "Video call"
        case nil: return nil
        }
    }
}

public enum ScribeSourceKind: String, CaseIterable, Sendable {
    case microphone
    case callAudio
    case names

    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .callAudio: return "Call audio"
        case .names: return "Names"
        }
    }
}

public enum ScribeSourceStatus: Equatable, Sendable {
    case on
    case off
    case needsPermission

    public var label: String {
        switch self {
        case .on: return "On"
        case .off: return "Off"
        case .needsPermission: return "Needs permission"
        }
    }
}

public struct ScribeSourceChip: Equatable, Sendable {
    public let kind: ScribeSourceKind
    public let status: ScribeSourceStatus
    /// What the chip means and, when permission is missing, what to do.
    public let detail: String
}

public enum ScribeSourceChips {
    /// Microphone: denied or restricted needs permission; macOS asks on the first press, so "not yet asked" is on.
    /// Call audio: only known once capture starts, so it reads on while capture can run, off otherwise.
    /// Names: the call window's names need Accessibility; without it Scribe still works, with colours and "Naming".
    public static func chips(microphone: PermissionState, captureAvailable: Bool, namesTrusted: Bool) -> [ScribeSourceChip] {
        let mic: ScribeSourceChip
        switch microphone {
        case .denied:
            mic = ScribeSourceChip(kind: .microphone, status: .needsPermission,
                detail: "Microphone access is off for Zeus. Open System Settings to turn it on.")
        case .authorized, .notDetermined:
            mic = ScribeSourceChip(kind: .microphone, status: .on, detail: "Your voice is captured.")
        }
        let call = captureAvailable
            ? ScribeSourceChip(kind: .callAudio, status: .on, detail: "The other side of a call is captured.")
            : ScribeSourceChip(kind: .callAudio, status: .off, detail: "Capture is not available right now.")
        let names = namesTrusted
            ? ScribeSourceChip(kind: .names, status: .on, detail: "Names come from the call window.")
            : ScribeSourceChip(kind: .names, status: .needsPermission,
                detail: "Allow Accessibility to read names from the call window.")
        return [mic, call, names]
    }
}

/// Who is speaking right now, from the newest transcript line that holds words.
public struct ScribeNowSpeaking: Equatable, Sendable {
    public let speaker: ScribeSpeaker
    /// The full name, "You", or "Naming…" while no name is known yet.
    public let name: String
    public let initials: String
    public let isNaming: Bool

    /// "Marie Dubois is speaking" or "Someone is speaking, the name is not known yet".
    public var spoken: String {
        isNaming ? "Someone is speaking, the name is not known yet" : "\(name) is speaking"
    }

    /// A bare "Speaker", "Speaker 2" or an unknown voice is a placeholder, never shown as a name.
    public static func isPlaceholder(_ speaker: ScribeSpeaker) -> Bool {
        switch speaker {
        case .you: return false
        case .unknown: return true
        case .participant(let label):
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "Speaker" { return true }
            guard trimmed.hasPrefix("Speaker ") else { return false }
            return Int(trimmed.dropFirst("Speaker ".count)) != nil
        }
    }

    public static func resolve(_ speaker: ScribeSpeaker) -> ScribeNowSpeaking {
        if isPlaceholder(speaker) {
            return ScribeNowSpeaking(speaker: speaker, name: "Naming\u{2026}", initials: "\u{2026}", isNaming: true)
        }
        let name = speaker.displayName
        return ScribeNowSpeaking(speaker: speaker, name: name, initials: ScribeInitials.of(name), isNaming: false)
    }

    /// The speaker of the newest segment with real words; nil before anyone has spoken.
    public static func current(in segments: [ScribeTranscriptSegment]) -> ScribeNowSpeaking? {
        guard let latest = segments.last(where: { ScribeTickerText.hasWords($0.text) }) else { return nil }
        return resolve(latest.speaker)
    }
}

/// The decorative waveform of the idle page. It is synthetic: the microphone stays off until the person presses
/// the capture button.
public enum ScribeBreathingWave {
    /// Seconds for one slow breath.
    public static let period: TimeInterval = 6

    /// Height of bar `index` of `count` at time `t`, 0...1. A gentle bump in the middle that swells and eases
    /// with the breath, never still and never loud.
    public static func level(index: Int, count: Int, t: TimeInterval) -> Double {
        guard count > 1, index >= 0, index < count, t.isFinite else { return 0.15 }
        let position = Double(index) / Double(count - 1)
        let envelope = sin(position * .pi)
        let breath = 0.5 + 0.5 * sin(2 * .pi * t / period)
        let ripple = 0.5 + 0.5 * sin(position * 9 + t * 0.9)
        let value = 0.12 + envelope * (0.25 + 0.45 * breath) * (0.55 + 0.45 * ripple)
        return min(1, max(0, value))
    }
}
