import Foundation

/// The chips on the Reminders page.
/// Membership is read from `ReminderFiltersBox`.
public enum ReminderFilter: String, CaseIterable, Identifiable, Sendable {
    case today = "Today", scheduled = "Scheduled", all = "All", flagged = "Flagged"
    public var id: String { rawValue }

    /// Today: due today or already overdue. Scheduled: has a due date. All. Flagged: marked important
    /// (EventKit does not expose Reminders' flag, so ZEUS reads high priority as flagged).
    public func includes(due: Date?, flagged: Bool, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        ReminderFiltersBox.includes(self, due: due, flagged: flagged, now: now, calendar: calendar)
    }
}

/// One-tap due times for a new reminder.
/// Each time is read from `ReminderFiltersBox`.
public enum ReminderQuickDue: String, CaseIterable, Identifiable, Sendable {
    case inAnHour = "In 1 hour", thisEvening = "This evening", tomorrowMorning = "Tomorrow 9:00", nextWeek = "Next week"
    public var id: String { rawValue }

    public func date(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        ReminderFiltersBox.quickDue(self, now: now, calendar: calendar)
    }
}

/// "pay rent friday at 5pm", "call Ana tomorrow 9:30", "water plants at 18:00": a title, a day and a time.
/// The clock and the title split are read from `ReminderFiltersBox`. The day still comes from `TodoQuickAdd`.
public enum ReminderDraft {
    public struct Parsed: Equatable, Sendable {
        public var title: String
        public var due: Date?
        public var hasTime: Bool
    }

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Parsed {
        let draft = ReminderFiltersBox.draft(text, now: now, calendar: calendar) { remaining in
            let day = TodoQuickAdd.parse(remaining, now: now, calendar: calendar)
            let due = day.due.flatMap { TodoQuickAdd.day($0, calendar: calendar) }
            return (title: day.title, due: due)
        }
        return Parsed(title: draft.title, due: draft.due, hasTime: draft.hasTime)
    }
}
