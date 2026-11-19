import Testing
@testable import Zeus

@Suite("Calendar permission grant", .serialized)
@MainActor
struct PermissionsCalendarGrantTests {
    @Test func aCalendarGrantReplansTheMeetingDetector() async {
        var follows = 0
        let model = PermissionsModel(eventAccess: .init(request: { _ in true }, calendarGranted: { follows += 1 }))
        await model.requestEventAccess(.calendar)
        #expect(follows == 1, "the detector reads the calendar now, not at a wake that may be a day away")
    }

    @Test func aCalendarRefusalOrAReminderGrantDoesNotReplan() async {
        var follows = 0
        let refused = PermissionsModel(eventAccess: .init(request: { _ in false }, calendarGranted: { follows += 1 }))
        await refused.requestEventAccess(.calendar)
        let reminders = PermissionsModel(eventAccess: .init(request: { _ in true }, calendarGranted: { follows += 1 }))
        await reminders.requestEventAccess(.reminders)
        #expect(follows == 0)
    }
}
