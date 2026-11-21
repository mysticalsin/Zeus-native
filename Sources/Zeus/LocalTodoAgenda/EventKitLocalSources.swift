import Foundation
import ZeusCore

#if canImport(EventKit)
import AppKit
import EventKit

/// Reads tasks and events the Mac already stores. Prompts only when a caller asks, and only for a full read.
enum EventKitLocalSources {
    static func map(_ status: EKAuthorizationStatus) -> LocalAccessStatus {
        switch status {
        case .fullAccess: .allowed
        case .denied, .writeOnly: .denied
        case .restricted: .restricted
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }

    static func kind(of source: EKSource) -> String {
        switch source.sourceType {
        case .local: "local"
        case .exchange: "exchange"
        case .calDAV: "calDAV"
        case .mobileMe: "mobileMe"
        case .subscribed: "subscribed"
        case .birthdays: "birthdays"
        @unknown default: "unknown"
        }
    }
}

enum MicrosoftLocalApp {
    static let outlook = "com.microsoft.Outlook"
    static let toDo = ["com.microsoft.to-do-mac", "com.microsoft.to-do"]
}

/// EventKit backed tasks, events and account names. The store is injected. The app probe is injected.
struct EventKitTodoAgendaReader: TodoSource, AgendaSource, LocalPresenceSource {
    var store: EKEventStore
    var eventStatus: () -> EKAuthorizationStatus
    var reminderStatus: () -> EKAuthorizationStatus
    var installed: (String) -> Bool

    init(store: EKEventStore,
         eventStatus: @escaping () -> EKAuthorizationStatus = { EKEventStore.authorizationStatus(for: .event) },
         reminderStatus: @escaping () -> EKAuthorizationStatus = { EKEventStore.authorizationStatus(for: .reminder) },
         installed: @escaping (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) {
        self.store = store
        self.eventStatus = eventStatus
        self.reminderStatus = reminderStatus
        self.installed = installed
    }

    func access() -> LocalAccessPair {
        LocalAccessPair(events: EventKitLocalSources.map(eventStatus()), reminders: EventKitLocalSources.map(reminderStatus()))
    }

    /// Asks only for a side that has not been asked. A denial is left as it is.
    func requestAccess() async -> LocalAccessPair {
        if access().events == .notAsked {
            _ = try? await store.requestFullAccessToEvents()
        }
        if access().reminders == .notAsked {
            _ = try? await store.requestFullAccessToReminders()
        }
        return access()
    }

    func presence() async -> LocalAppPresence {
        var titles: [String] = []
        if access().events == .allowed { titles += microsoftTitles(store.calendars(for: .event)) }
        if access().reminders == .allowed { titles += microsoftTitles(store.calendars(for: .reminder)) }
        return LocalAppPresence(
            outlookInstalled: installed(MicrosoftLocalApp.outlook),
            toDoInstalled: MicrosoftLocalApp.toDo.contains(where: installed),
            microsoftSources: Array(Set(titles)).sorted())
    }

    func loadTodos(now: Date, timeZone: TimeZone) async -> [LocalTodoRecord] {
        guard access().reminders == .allowed else { return [] }
        let lists = store.calendars(for: .reminder).filter { isMicrosoft($0) }
        guard !lists.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: lists)
        let reminders = await fetched(predicate)
        return reminders.filter { !$0.isCompleted }.map { record(from: $0, viewZone: timeZone) }
    }

    func loadAgenda(now: Date, timeZone: TimeZone) async -> [LocalAgendaRecord] {
        guard access().events == .allowed else { return [] }
        let calendars = store.calendars(for: .event).filter { isMicrosoft($0) }
        guard !calendars.isEmpty else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDay = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -1, to: startDay) ?? startDay
        let end = calendar.date(byAdding: .day, value: 2, to: startDay) ?? startDay
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map { record(from: $0, viewZone: timeZone) }
    }

    private func isMicrosoft(_ calendar: EKCalendar) -> Bool {
        MicrosoftAccountMatch.isMicrosoft(sourceName: calendar.source.title, sourceKind: EventKitLocalSources.kind(of: calendar.source))
    }

    private func microsoftTitles(_ calendars: [EKCalendar]) -> [String] {
        calendars.filter(isMicrosoft).map { $0.source.title }
    }

    private func fetched(_ predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func record(from reminder: EKReminder, viewZone: TimeZone) -> LocalTodoRecord {
        let components = reminder.dueDateComponents
        let zone = components?.timeZone ?? viewZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let due = components.flatMap { calendar.date(from: $0) }
        return LocalTodoRecord(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            listName: reminder.calendar.title,
            sourceName: reminder.calendar.source.title,
            sourceKind: EventKitLocalSources.kind(of: reminder.calendar.source),
            due: due,
            isAllDay: components?.hour == nil,
            timeZoneIdentifier: zone.identifier,
            completed: reminder.isCompleted)
    }

    private func record(from event: EKEvent, viewZone: TimeZone) -> LocalAgendaRecord {
        let zone = event.timeZone ?? viewZone
        let series = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? event.calendarItemIdentifier
        return LocalAgendaRecord(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            seriesID: series,
            title: event.title ?? "",
            calendarName: event.calendar.title,
            sourceName: event.calendar.source.title,
            sourceKind: EventKitLocalSources.kind(of: event.calendar.source),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: zone.identifier,
            isRecurring: event.hasRecurrenceRules)
    }
}
#endif
