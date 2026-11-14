import Foundation

// What the meeting-start detector reads: the calendar slot, the call apps, which one holds the microphone, and
// the rules that turn them into one meeting. Pure value types and rules; the app gathers the signals.

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

public struct ScribeCalendarSlot: Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date?
    /// Display names of the invitees. Never email addresses: `ScribeAttendeeNames.clean` drops those.
    public var attendeeNames: [String]
    /// The event carries a call link (Teams, Zoom, Meet, Webex...). Only the meeting-start detector reads it.
    public var hasCallLink: Bool

    public init(id: String, title: String, start: Date, end: Date? = nil, attendeeNames: [String] = [],
                hasCallLink: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendeeNames = ScribeAttendeeNames.clean(attendeeNames)
        self.hasCallLink = hasCallLink
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
    /// The person already agreed, once, that Zeus may start notes by itself (`ScribeAutoStartConsent`).
    public var autoConsentGiven: Bool
    /// Whether each call app's call window is still on screen. Missing means unknown, which never ends a call.
    public var callWindows: [ScribeCallApp: ScribeCallWindowState]

    public init(date: Date, slots: [ScribeCalendarSlot] = [], micApps: [ScribeCallApp] = [],
                presentApps: [ScribeCallApp] = [], mode: ScribeAutoStartMode = .ask,
                micPermissionGranted: Bool = false, activity: ScribeActivity = .idle,
                autoConsentGiven: Bool = false, callWindows: [ScribeCallApp: ScribeCallWindowState] = [:]) {
        self.date = date
        self.slots = slots
        self.micApps = micApps
        self.presentApps = presentApps
        self.mode = mode
        self.micPermissionGranted = micPermissionGranted
        self.activity = activity
        self.autoConsentGiven = autoConsentGiven
        self.callWindows = callWindows
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

extension ScribeMeetingStartPolicy {
    /// Another calendar meeting (with a call link) about to start while one is recording: from this long before
    /// its start until `nextLateWindow` after. Never the meeting already recording or one already offered.
    public static let nextLeadWindow: TimeInterval = 120
    public static let nextLateWindow: TimeInterval = 30

    public static func nextSlot(in slots: [ScribeCalendarSlot], excluding keys: Set<String>, at date: Date) -> ScribeCalendarSlot? {
        slots.filter { slot in
            guard slot.hasCallLink, !keys.contains(slot.id) else { return false }
            if let end = slot.end, date >= end { return false }
            let untilStart = slot.start.timeIntervalSince(date)
            return untilStart <= nextLeadWindow && -untilStart <= nextLateWindow
        }.min { lhs, rhs in
            let l = lhs.start.timeIntervalSince(date)
            let r = rhs.start.timeIntervalSince(date)
            return l != r ? l < r : lhs.id < rhs.id
        }
    }
}

public enum ScribeCallWindowState: Equatable, Sendable {
    case unknown
    case present
    case gone
}

/// Is the call's own window still open? Read from window titles, which macOS only shows for other apps when
/// Screen Recording is already allowed; otherwise the answer is `.unknown` and never ends a recording. Only apps
/// with a reliable title are judged: Teams and FaceTime are left to the microphone signal.
public enum ScribeCallWindow {
    /// Nil when this app has no reliable call-window title.
    public static func isCallWindow(_ app: ScribeCallApp, title: String) -> Bool? {
        let lowered = title.lowercased()
        switch app {
        case .zoom:
            return ["zoom meeting", "zoom webinar", "meeting controls"].contains { lowered.contains($0) }
        case .meet:
            return ScribeCallDetection.isMeetTitle(title)
        case .teams:
            return nil
        case .other(let name):
            switch name {
            case "Slack": return lowered.contains("huddle")
            case "Webex": return lowered.contains("webex meeting")
            default: return nil
            }
        }
    }

    /// `complete` is false when any window's title could not be read.
    public static func state(app: ScribeCallApp, titles: [String], complete: Bool) -> ScribeCallWindowState {
        guard complete, isCallWindow(app, title: "") != nil else { return .unknown }
        return titles.contains { isCallWindow(app, title: $0) == true } ? .present : .gone
    }
}
