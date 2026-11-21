import Foundation

/// An event the app already has. The scheduler does not create one.
public struct InAppOccasion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case meeting
        case reminder
        case focusEnd
    }

    public var id: String
    public var title: String
    public var start: Date
    public var kind: Kind

    public init(id: String, title: String, start: Date, kind: Kind) {
        self.id = id
        self.title = title
        self.start = start
        self.kind = kind
    }
}

public struct HeadsUpCue: Equatable, Sendable {
    public var occasionID: String
    public var title: String
    public var kind: InAppOccasion.Kind
    public var fireAt: Date

    public init(occasionID: String, title: String, kind: InAppOccasion.Kind, fireAt: Date) {
        self.occasionID = occasionID
        self.title = title
        self.kind = kind
        self.fireAt = fireAt
    }
}

public enum MeetingHeadsUpPhase: Equatable, Sendable {
    case off
    case idle
    case armed
    case showing
}

public struct MeetingHeadsUpPlan: Equatable, Sendable {
    public var phase: MeetingHeadsUpPhase
    public var cues: [HeadsUpCue]
    public var createdEvents: [String]

    public init(phase: MeetingHeadsUpPhase, cues: [HeadsUpCue], createdEvents: [String]) {
        self.phase = phase
        self.cues = cues
        self.createdEvents = createdEvents
    }
}

/// Preferences the live and snapshot notification pages share. The master switch defaults off.
public struct MeetingHeadsUpSettings: Equatable, Sendable {
    public static let enabledKey = "notify.meetingHeadsUp"
    public static let leadKey = "notify.calendarLead"
    public static let remindersKey = "notify.reminders"
    public static let focusKey = "notify.focus"

    public var enabled: Bool
    public var calendarLeadMinutes: Int
    public var reminders: Bool
    public var focus: Bool

    public init(enabled: Bool, calendarLeadMinutes: Int, reminders: Bool, focus: Bool) {
        self.enabled = enabled
        self.calendarLeadMinutes = min(180, max(0, calendarLeadMinutes))
        self.reminders = reminders
        self.focus = focus
    }

    public static func load(_ defaults: UserDefaults) -> MeetingHeadsUpSettings {
        let lead = (defaults.object(forKey: leadKey) as? Int) ?? 5
        return MeetingHeadsUpSettings(
            enabled: (defaults.object(forKey: enabledKey) as? Bool) ?? false,
            calendarLeadMinutes: lead,
            reminders: (defaults.object(forKey: remindersKey) as? Bool) ?? true,
            focus: (defaults.object(forKey: focusKey) as? Bool) ?? true
        )
    }

    public func save(_ defaults: UserDefaults) {
        defaults.set(enabled, forKey: Self.enabledKey)
        defaults.set(calendarLeadMinutes, forKey: Self.leadKey)
        defaults.set(reminders, forKey: Self.remindersKey)
        defaults.set(focus, forKey: Self.focusKey)
    }
}

/// Local, in-app heads-up. It never writes a calendar event and it stays idle until the user turns it on.
public enum MeetingHeadsUpScheduler {
    public static let createsCalendarEvents = false

    public static func plan(
        settings: MeetingHeadsUpSettings,
        occasions: [InAppOccasion],
        now: Date,
        scribeWatchedIDs: Set<String> = []
    ) -> MeetingHeadsUpPlan {
        guard settings.enabled else {
            return MeetingHeadsUpPlan(phase: .off, cues: [], createdEvents: [])
        }
        var cues: [HeadsUpCue] = []
        for occasion in occasions {
            if occasion.kind == .meeting, scribeWatchedIDs.contains(occasion.id) { continue }
            guard let fireAt = fireDate(settings: settings, occasion: occasion) else { continue }
            cues.append(HeadsUpCue(occasionID: occasion.id, title: occasion.title, kind: occasion.kind, fireAt: fireAt))
        }
        return MeetingHeadsUpPlan(phase: phase(cues: cues, occasions: occasions, now: now), cues: cues, createdEvents: [])
    }

    /// Meeting ids Scribe already covers inside its lead window. Reminders and focus are not included.
    /// This reads the slots it is given. It does not read a calendar and it does not start Scribe.
    public static func scribeWatchedIDs(slots: [ScribeCalendarSlot], now: Date) -> Set<String> {
        var ids = Set<String>()
        if let slot = ScribeMeetingStartPolicy.upcomingSlot(in: slots, at: now) {
            ids.insert(slot.id)
        }
        if let slot = ScribeMeetingStartPolicy.startedSlot(in: slots, at: now) {
            ids.insert(slot.id)
        }
        return ids
    }

    private static func fireDate(settings: MeetingHeadsUpSettings, occasion: InAppOccasion) -> Date? {
        switch occasion.kind {
        case .meeting:
            guard settings.calendarLeadMinutes > 0 else { return nil }
            return occasion.start.addingTimeInterval(-Double(settings.calendarLeadMinutes) * 60)
        case .reminder:
            guard settings.reminders else { return nil }
            return occasion.start
        case .focusEnd:
            guard settings.focus else { return nil }
            return occasion.start
        }
    }

    private static func phase(cues: [HeadsUpCue], occasions: [InAppOccasion], now: Date) -> MeetingHeadsUpPhase {
        let starts = Dictionary(uniqueKeysWithValues: occasions.map { ($0.id, $0.start) })
        let showing = cues.contains { cue in
            guard let start = starts[cue.occasionID] else { return false }
            return cue.fireAt <= now && now <= start
        }
        if showing { return .showing }
        if cues.contains(where: { $0.fireAt > now }) { return .armed }
        return .idle
    }
}
