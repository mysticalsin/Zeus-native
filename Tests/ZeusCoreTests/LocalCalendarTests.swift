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
        #expect(LocalCalendarAccess.outlookVisible(sources: [.exchange]))
        #expect(!LocalCalendarAccess.outlookVisible(sources: [.other]))
        #expect(LocalCalendarAccess.outlookReport(status: .denied, sources: [.exchange]).contains("denied"))
        #expect(!LocalCalendarAccess.outlookReport(status: .denied, sources: [.exchange]).contains("not in the Mac's calendars"))
        #expect(LocalCalendarAccess.outlookReport(status: .notAsked, sources: []).contains("not been asked"))
        #expect(!LocalCalendarAccess.outlookReport(status: .notAsked, sources: []).contains("not in the Mac's calendars"))
    }

    @Test func outlookIsVisibleOnlyWhenEventKitListsThatAccount() {
        #expect(LocalCalendarAccess.outlookVisible(sources: [.other, .exchange]))
        #expect(!LocalCalendarAccess.outlookVisible(sources: [.other]))
        #expect(LocalCalendarAccess.outlookReport(status: .allowed, sources: [.other]).contains("not in the Mac's calendars"))
        #expect(LocalCalendarAccess.outlookReport(status: .allowed, sources: [.exchange]).contains("visible"))
    }

    @Test func outlookIsNotScripted() {
        #expect(!OutlookCalendarBridge.usesAppleScript)
        #expect(OutlookCalendarBridge.finding.contains("EventKit"))
        #expect(!OutlookCalendarBridge.finding.contains("tell application"))
    }
}
