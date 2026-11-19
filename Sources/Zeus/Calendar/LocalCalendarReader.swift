import EventKit
import Foundation

/// Reads the Mac's calendars. Access is requested only when the agenda is turned on, and only to read.
@MainActor
enum LocalCalendarReader {
    private static let store = EKEventStore()

    static var status: LocalCalendarAccess.Status {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .allowed
        case .denied, .writeOnly: .denied
        case .restricted: .restricted
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }

    /// The reader has no caller, so it does not ask for calendar access.
    static func ensureAccess() async -> LocalCalendarAccess.Status { status }

    static func sourceKinds() -> [LocalCalendarAccess.SourceKind] {
        guard status == .allowed else { return [] }
        return store.calendars(for: .event).map { calendar in
            calendar.source.sourceType == .exchange ? .exchange : .other
        }
    }

    static var outlookReport: String {
        LocalCalendarAccess.outlookReport(status: status, sources: sourceKinds())
    }
}
