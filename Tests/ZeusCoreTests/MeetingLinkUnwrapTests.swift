import Foundation
import Testing
@testable import ZeusCore

@Suite struct MeetingLinkUnwrapTests {
    private static let teamsInner = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22t%22%7d"

    private static func safeLink(_ inner: String, host: String = "eur02.safelinks.protection.outlook.com") -> String {
        let encoded = inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? inner
        return "https://\(host)/?url=\(encoded)&data=05%7C02%7Cx&sdata=abc&reserved=0"
    }

    @Test func safeLinksTeamsMeetupJoinIsUnwrapped() {
        let url = MeetingLink.find(in: [Self.safeLink(Self.teamsInner)])
        #expect(url?.host == "teams.microsoft.com")
        #expect(url?.path.hasPrefix("/l/meetup-join/") == true)
    }

    @Test func safeLinksTeamsMeetFormIsUnwrapped() {
        let url = MeetingLink.find(in: [Self.safeLink("https://teams.microsoft.com/meet/123456789012?p=AbCdEf")])
        #expect(url?.absoluteString == "https://teams.microsoft.com/meet/123456789012?p=AbCdEf")
    }

    @Test func safeLinksZoomIsUnwrapped() {
        let url = MeetingLink.find(in: [Self.safeLink("https://us02web.zoom.us/j/123456789?pwd=xyz", host: "nam11.safelinks.protection.outlook.com")])
        #expect(url?.host == "us02web.zoom.us")
    }

    @Test func googleRedirectMeetIsUnwrapped() {
        let url = MeetingLink.find(in: ["https://www.google.com/url?q=https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij&sa=D&source=calendar&usd=2"])
        #expect(url?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func wrapperAroundANonMeetingUrlIsNotAMeetingLink() {
        #expect(MeetingLink.find(in: [Self.safeLink("https://example.com/agenda.pdf")]) == nil)
        #expect(MeetingLink.find(in: ["https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fx&sa=D"]) == nil)
        #expect(MeetingLink.find(in: ["https://evilsafelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fx"]) == nil)
    }

    @Test func aDirectLinkIsStillFoundUnchanged() {
        #expect(MeetingLink.find(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0"])?.host == "teams.microsoft.com")
        #expect(MeetingLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func aWrappedLinkInsideNotesWithProseIsFound() {
        let notes = "Hi all,\nJoin the call here: \(Self.safeLink(Self.teamsInner)) before 10am.\nThanks!"
        let url = MeetingLink.find(in: [nil, "Room 4", notes])
        #expect(url?.host == "teams.microsoft.com")
    }

    @Test func aWrapperLoopIsGivenUpOn() {
        let loop = "https://www.google.com/url?q=https%3A%2F%2Fwww.google.com%2Furl%3Fq%3Dhttps%253A%252F%252Fwww.google.com%252Furl%253Fq%253Dhttps%25253A%25252F%25252Fmeet.google.com%25252Fabc-defg-hij"
        #expect(MeetingLink.find(in: [loop]) == nil)
    }

    @Test func callAppFollowsTheUnwrappedLink() {
        let teams = MeetingLink.find(in: [Self.safeLink(Self.teamsInner)])
        #expect(ScribeUpNext.callApp(link: teams) == .teams)
        let meet = MeetingLink.find(in: ["https://www.google.com/url?q=https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij&sa=D"])
        #expect(ScribeUpNext.callApp(link: meet) == .meet)
        let zoom = MeetingLink.find(in: [Self.safeLink("https://us02web.zoom.us/j/1")])
        #expect(ScribeUpNext.callApp(link: zoom) == .zoom)
    }
}
