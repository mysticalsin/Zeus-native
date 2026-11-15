import EventKit
import Foundation
import ZeusCore

/// The one reader of the calendar for Scribe: the meeting-start detector and the idle page's "Up next" card both
/// read through it, so they agree on what a meeting is. It reads only when full calendar access was already
/// granted elsewhere and never asks for it. Only display names leave an event.
@MainActor
final class ScribeCalendarReader {
    static let shared = ScribeCalendarReader()

    /// What one calendar event says, as plain values. `slot(from:)` is the rule; the reader only maps into it.
    struct Event: Equatable, Sendable {
        var identifier: String?
        var title: String?
        var start: Date?
        var end: Date?
        var isAllDay: Bool
        var isCanceled: Bool
        var hasAttendees: Bool
        /// The current user answered Decline.
        var declinedByMe: Bool
        /// The other guests' display names.
        var attendeeNames: [String]
        /// Every text of the event that may hold a call link: its URL, location and notes.
        var linkTexts: [String?]
    }

    private lazy var store = EKEventStore()

    var isReadable: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// The meetings that overlap `from ..< to`, or none without access.
    func slots(from: Date, to: Date) -> [ScribeCalendarSlot] {
        guard isReadable else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).compactMap { Self.slot(from: Self.event(from: $0)) }
    }

    private static func event(from event: EKEvent) -> Event {
        let others = (event.attendees ?? []).filter { !$0.isCurrentUser }
        return Event(
            identifier: event.eventIdentifier, title: event.title, start: event.startDate, end: event.endDate,
            isAllDay: event.isAllDay, isCanceled: event.status == .canceled, hasAttendees: event.hasAttendees,
            declinedByMe: (event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined },
            attendeeNames: others.compactMap(\.name),
            linkTexts: [event.url?.absoluteString, event.location, event.notes])
    }

    /// A meeting, not a reminder to yourself or a day marker: it has guests or a call link, it was not cancelled,
    /// and the current user did not decline it.
    nonisolated static func slot(from event: Event) -> ScribeCalendarSlot? {
        guard !event.isAllDay, !event.isCanceled, !event.declinedByMe, let start = event.start else { return nil }
        let link = MeetingLink.find(in: event.linkTexts)
        guard event.hasAttendees || link != nil else { return nil }
        let base = event.identifier ?? event.title ?? "event"
        return ScribeCalendarSlot(
            id: "\(base)@\(Int(start.timeIntervalSince1970))",
            title: event.title ?? "Meeting",
            start: start,
            end: event.end,
            // Display names only; the slot drops anything that looks like an address.
            attendeeNames: event.attendeeNames,
            hasCallLink: link != nil,
            callApp: ScribeUpNext.callApp(link: link))
    }
}
