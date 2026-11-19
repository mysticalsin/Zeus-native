import Foundation
import Observation
import ZeusCore

/// The next calendar meeting, for the idle Scribe page's "Up next" card.
///
/// Reads through `ScribeCalendarReader`, the same reader as the meeting-start detector: events are read only when
/// full calendar access was already granted elsewhere, and this never asks for it. Without access the card just
/// says Scribe is ready. The model reads the calendar when the page opens or Zeus becomes the front app again; it
/// runs no timer.
@MainActor
@Observable
final class ScribeUpNextModel {
    static let shared = ScribeUpNextModel()

    private(set) var meeting: ScribeUpNextMeeting?

    /// How far ahead the card looks.
    private static let lookAhead: TimeInterval = 24 * 3_600

    var calendarReadable: Bool { ScribeCalendarReader.shared.isReadable }

    func refresh(now: Date = Date()) {
        guard calendarReadable else {
            meeting = nil
            return
        }
        let slots = ScribeCalendarReader.shared.slots(from: now.addingTimeInterval(-ScribeUpNext.openEndedGrace),
                                                      to: now.addingTimeInterval(Self.lookAhead))
        meeting = ScribeUpNext.pick(slots.map { ScribeUpNextMeeting(slot: $0, app: $0.callApp) }, now: now)
    }

    /// Snapshots and previews show a fixed meeting without touching the calendar.
    func seedForSnapshot(_ meeting: ScribeUpNextMeeting?) { self.meeting = meeting }
}
