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

    /// Asks the first time the feature is used. A later call does not prompt again.
    static func ensureAccess() async -> LocalCalendarAccess.Status {
        if status == .allowed || status == .denied || status == .restricted { return status }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        return granted ? .allowed : status
    }

    static func sourceNames() -> [String] {
        guard status == .allowed else { return [] }
        return store.calendars(for: .event).map(\.source.title)
    }

    static var outlookReport: String {
        LocalCalendarAccess.outlookReport(calendarSources: sourceNames())
    }
}
