import Testing
@testable import ZeusCore

@Suite("Local calendar")
struct LocalCalendarTests {
    @Test func accessMapsWithoutClaimingAGrant() {
        #expect(LocalCalendarAccess.map(fullAccess: true, denied: false, restricted: false, asked: true) == .allowed)
        #expect(LocalCalendarAccess.map(fullAccess: false, denied: true, restricted: false, asked: true) == .denied)
        #expect(LocalCalendarAccess.map(fullAccess: false, denied: false, restricted: true, asked: true) == .restricted)
        #expect(LocalCalendarAccess.map(fullAccess: false, denied: false, restricted: false, asked: false) == .notAsked)
    }

    @Test func aTitleThatSaysExchangeIsNotTheAccountType() {
        #expect(!LocalCalendarAccess.outlookVisible(calendarSources: ["Exchange Work"]))
        #expect(LocalCalendarAccess.outlookReport(status: .denied, sources: []).contains("denied"))
        #expect(!LocalCalendarAccess.outlookReport(status: .denied, sources: []).contains("not in the Mac's calendars"))
        #expect(LocalCalendarAccess.outlookReport(status: .notAsked, sources: []).contains("not been asked"))
    }

    @Test func outlookIsVisibleOnlyWhenEventKitListsThatAccount() {
        #expect(LocalCalendarAccess.outlookVisible(calendarSources: ["iCloud", "Exchange Work"]))
        #expect(!LocalCalendarAccess.outlookVisible(calendarSources: ["iCloud", "On My Mac"]))
        #expect(LocalCalendarAccess.outlookReport(calendarSources: ["iCloud"]).contains("not in the Mac's calendars"))
        #expect(LocalCalendarAccess.outlookReport(calendarSources: ["Outlook"]).contains("visible"))
    }

    @Test func outlookIsNotScripted() {
        #expect(!OutlookCalendarBridge.usesAppleScript)
        #expect(OutlookCalendarBridge.finding.contains("EventKit"))
        #expect(!OutlookCalendarBridge.finding.contains("tell application"))
    }
}
