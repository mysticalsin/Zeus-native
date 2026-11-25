import Foundation
import Testing
@testable import ZeusCore

@Suite("Meeting alert")
struct MeetingAlertTests {
    @Test func theBannerIsAShortRowAndDismissesItself() {
        #expect(MeetingAlert.height <= 48)
        #expect(MeetingAlert.width <= 440)
        #expect(MeetingAlert.height == ScribeMeetingCardMetrics.height)
        #expect(MeetingAlert.width == ScribeMeetingCardMetrics.width)
        #expect(MeetingAlert.dismissAfter == 10)
        #expect(MeetingAlert.recordsOnlyWhenTapped)
    }

    @Test func aLinkNamesTheCallAndTheRowShowsTitleTimeAndApp() {
        #expect(MeetingAlert.app(link: "https://teams.microsoft.com/l/meetup-join/abc") == .teams)
        #expect(MeetingAlert.app(link: "https://us02web.zoom.us/j/1") == .zoom)
        #expect(MeetingAlert.app(link: "https://meet.google.com/abc-defg-hij") == .meet)
        #expect(MeetingAlert.app(link: "https://company.webex.com/meet/ada") == .other("Webex"))
        #expect(MeetingAlert.app(link: "https://example.com/zoom") == nil)
        let start = Date(timeIntervalSince1970: 10_000)
        let row = MeetingAlert.model(title: "Design review", start: start, now: start.addingTimeInterval(-600), app: .zoom)
        #expect(row.title == "Design review")
        #expect(row.when == "in 10 min")
        #expect(row.appName == "Zoom")
        #expect(row.symbol == "video")
        #expect(MeetingAlert.when(untilStart: 10) == "Now")
        #expect(MeetingAlert.when(untilStart: -120) == "Started")
    }
}
