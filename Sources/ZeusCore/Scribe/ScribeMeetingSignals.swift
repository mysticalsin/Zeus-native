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
    /// The call app of the event's link, set by the calendar reader. Nil without a link.
    public var callApp: ScribeCallApp?
    /// The call link itself, when the calendar event holds one. Only the meeting card's Join action reads it;
    /// it is never logged or stored.
    public var callLink: URL?

    public init(id: String, title: String, start: Date, end: Date? = nil, attendeeNames: [String] = [],
                hasCallLink: Bool = false, callApp: ScribeCallApp? = nil, callLink: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendeeNames = ScribeAttendeeNames.clean(attendeeNames)
        self.hasCallLink = hasCallLink
        self.callApp = callApp
        self.callLink = callLink
    }
}

/// One meeting, identified so the same meeting never triggers twice.
public struct ScribeMeeting: Equatable, Sendable {
    /// The calendar slot id when a calendar event matched, else "call:<app>".
    public var key: String
    public var title: String
    /// The app of the call: the one holding the microphone for a live meeting, else the app of the event's link.
    public var callApp: ScribeCallApp?
    public var slot: ScribeCalendarSlot?
    /// A call app holds the microphone for this meeting now.
    public var isLive: Bool

    public init(key: String, title: String, callApp: ScribeCallApp?, slot: ScribeCalendarSlot? = nil,
                isLive: Bool = false) {
        self.key = key
        self.title = title
        self.callApp = callApp
        self.slot = slot
        self.isLive = isLive
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
    /// What the app read at this moment to decide a start: Scribe's phase, Microphone access, and whether an
    /// automatic start may count down. The detector never asks for a permission.
    public var context: ScribeStartContext
    /// Whether each call app's call window is still on screen. Missing means unknown, which never ends a call.
    public var callWindows: [ScribeCallApp: ScribeCallWindowState]

    public init(date: Date, slots: [ScribeCalendarSlot] = [], micApps: [ScribeCallApp] = [],
                presentApps: [ScribeCallApp] = [], mode: ScribeAutoStartMode = .ask,
                context: ScribeStartContext = ScribeStartContext(),
                callWindows: [ScribeCallApp: ScribeCallWindowState] = [:]) {
        self.date = date
        self.slots = slots
        self.micApps = micApps
        self.presentApps = presentApps
        self.mode = mode
        self.context = context
        self.callWindows = callWindows
    }

    /// A live meeting: a call app holds the microphone. It is the calendar meeting that call belongs to, else a
    /// call with no calendar behind it. Otherwise a scheduled meeting: a calendar event that has started and
    /// whose call, if any, has not begun. An open app alone (Teams is always open) is not a meeting.
    public var candidate: ScribeMeeting? {
        if let app = micApps.first {
            if let slot = ScribeMeetingStartPolicy.liveSlot(in: slots, micApps: micApps, at: date) {
                return ScribeMeeting(key: slot.id, title: Self.title(of: slot),
                                     callApp: ScribeMeetingStartPolicy.pairedApp(for: slot, micApps: micApps),
                                     slot: slot, isLive: true)
            }
            return ScribeMeeting(key: "call:\(ScribeCallDetection.displayName(app))", title: "Call", callApp: app,
                                 isLive: true)
        }
        guard let slot = ScribeMeetingStartPolicy.startedSlot(in: slots, at: date) else { return nil }
        return ScribeMeeting(key: slot.id, title: Self.title(of: slot), callApp: slot.callApp, slot: slot)
    }

    /// The heads-up meeting: the closest calendar meeting that starts within `leadWindow` and has not ended.
    public var upcoming: ScribeMeeting? { upcoming(excluding: []) }

    /// The same, skipping the slots in `excluded` (the ones already announced or answered).
    public func upcoming(excluding excluded: Set<String>) -> ScribeMeeting? {
        guard let slot = ScribeMeetingStartPolicy.upcomingSlot(in: slots, excluding: excluded, at: date) else { return nil }
        return ScribeMeeting(key: slot.id, title: Self.title(of: slot), callApp: slot.callApp, slot: slot)
    }

    static func title(of slot: ScribeCalendarSlot) -> String {
        let title = slot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Meeting" : title
    }
}

public enum ScribeMeetingStartPolicy {
    /// A calendar event counts from this long before it starts...
    public static let leadWindow: TimeInterval = 120
    /// ...until this long after.
    public static let lateWindow: TimeInterval = 300

    /// The app of a call app holding the microphone that belongs to this slot. A slot whose link is one of the known
    /// call apps pairs only with that app; any other slot pairs with the first app that holds the microphone.
    public static func pairedApp(for slot: ScribeCalendarSlot, micApps: [ScribeCallApp]) -> ScribeCallApp? {
        if let app = slot.callApp, [.teams, .zoom, .meet].contains(app) {
            return micApps.contains(app) ? app : nil
        }
        return micApps.first
    }

    /// The calendar meeting a live call belongs to: a slot with a link, from `leadWindow` before its start until
    /// its end (or `lateWindow` after the start when it has no end), whose app holds the microphone. Among slots
    /// already started the latest start wins; a slot not yet started pairs only when none has started.
    public static func liveSlot(in slots: [ScribeCalendarSlot], micApps: [ScribeCallApp], at date: Date) -> ScribeCalendarSlot? {
        let paired = slots.filter { slot in
            guard slot.hasCallLink, pairedApp(for: slot, micApps: micApps) != nil else { return false }
            let end = slot.end ?? slot.start.addingTimeInterval(lateWindow)
            return date >= slot.start.addingTimeInterval(-leadWindow) && date < end
        }
        let started = paired.filter { $0.start <= date }
        if started.isEmpty {
            return paired.min { lhs, rhs in lhs.start != rhs.start ? lhs.start < rhs.start : lhs.id < rhs.id }
        }
        return latestStart(started)
    }

    /// A calendar meeting that has started, with or without a call: `lateWindow` from its start, not ended. The
    /// calendar reader already keeps only events with guests or a link. The latest start wins.
    public static func startedSlot(in slots: [ScribeCalendarSlot], at date: Date) -> ScribeCalendarSlot? {
        latestStart(slots.filter { slot in
            let since = date.timeIntervalSince(slot.start)
            if let end = slot.end, date >= end { return false }
            return since >= 0 && since <= lateWindow
        })
    }

    /// A calendar meeting that has not started yet: it starts within `leadWindow` (`0 < start - date`, so a meeting
    /// at its start time is `startedSlot`'s) and has not ended. The closest start wins.
    public static func upcomingSlot(in slots: [ScribeCalendarSlot], excluding excluded: Set<String> = [],
                                    at date: Date) -> ScribeCalendarSlot? {
        slots.filter { slot in
            guard !excluded.contains(slot.id) else { return false }
            if let end = slot.end, date >= end { return false }
            let until = slot.start.timeIntervalSince(date)
            return until > 0 && until <= leadWindow
        }.min { lhs, rhs in lhs.start != rhs.start ? lhs.start < rhs.start : lhs.id < rhs.id }
    }

    private static func latestStart(_ slots: [ScribeCalendarSlot]) -> ScribeCalendarSlot? {
        slots.max { lhs, rhs in lhs.start != rhs.start ? lhs.start < rhs.start : lhs.id > rhs.id }
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

/// Names of the people on a calendar invite, as display names only.
public enum ScribeAttendeeNames {
    /// Trimmed, deduplicated, in order. An entry that is an email address (or holds an `@`) is dropped: an
    /// address never reaches a transcript, a suggestion or a saved file.
    public static func clean(_ names: [String], limit: Int = 50) -> [String] {
        var seen: Set<String> = []
        var kept: [String] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("@"), !name.contains("://"), name.count <= 80 else { continue }
            guard seen.insert(key(name)).inserted else { continue }
            kept.append(name)
            if kept.count >= limit { break }
        }
        return kept
    }

    /// Case, accent and spacing differences do not make two names two people.
    public static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
