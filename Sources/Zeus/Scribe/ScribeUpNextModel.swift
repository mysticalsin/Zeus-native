import EventKit
import Foundation
import Observation
import ZeusCore

/// The next calendar meeting, for the idle Scribe page's "Up next" card.
///
/// Same rules as the call popup's watcher: events are read only when full calendar access was already granted
/// elsewhere, and this never asks for it. Without access the card just says Scribe is ready. The model reads the
/// calendar when the page opens or Zeus becomes the front app again; it runs no timer.
@MainActor
@Observable
final class ScribeUpNextModel {
    static let shared = ScribeUpNextModel()

    private(set) var meeting: ScribeUpNextMeeting?
    @ObservationIgnored private lazy var store = EKEventStore()

    /// How far ahead the card looks.
    private static let lookAhead: TimeInterval = 24 * 3_600

    var calendarReadable: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func refresh(now: Date = Date()) {
        guard calendarReadable else {
            meeting = nil
            return
        }
        let from = now.addingTimeInterval(-ScribeUpNext.openEndedGrace)
        let predicate = store.predicateForEvents(withStart: from, end: now.addingTimeInterval(Self.lookAhead), calendars: nil)
        var found: [ScribeUpNextMeeting] = []
        for event in store.events(matching: predicate) {
            if let candidate = Self.candidate(from: event) { found.append(candidate) }
        }
        meeting = ScribeUpNext.pick(found, now: now)
    }

    /// Snapshots and previews show a fixed meeting without touching the calendar.
    func seedForSnapshot(_ meeting: ScribeUpNextMeeting?) { self.meeting = meeting }

    private static func candidate(from event: EKEvent) -> ScribeUpNextMeeting? {
        guard !event.isAllDay, event.status != .canceled, let start = event.startDate else { return nil }
        let link = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        // A meeting, not a reminder to yourself: it has guests or a call link.
        guard event.hasAttendees || link != nil else { return nil }
        let base = event.eventIdentifier ?? event.title ?? "event"
        let slot = ScribeCalendarSlot(
            id: "\(base)@\(Int(start.timeIntervalSince1970))",
            title: event.title ?? "Meeting",
            start: start,
            end: event.endDate,
            // Display names only; the slot drops anything that looks like an address.
            attendeeNames: (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(\.name)
        )
        return ScribeUpNextMeeting(slot: slot, app: ScribeUpNext.callApp(link: link))
    }
}
