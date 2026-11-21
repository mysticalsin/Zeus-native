import Foundation
import Testing
@testable import ZeusCore

@Suite("Meeting prompt")
struct MeetingPromptTests {
    private func start(minutes: Double) -> (Date, Date) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return (now.addingTimeInterval(minutes * 60), now)
    }

    @Test func theLeadStaysBetweenFiveAndTen() {
        #expect(MeetingPrompt.defaultLeadMinutes == 5)
        #expect(MeetingPrompt.leadMinutes(5) == 5)
        #expect(MeetingPrompt.leadMinutes(10) == 10)
        #expect(MeetingPrompt.leadMinutes(1) == 5)
        #expect(MeetingPrompt.leadMinutes(30) == 10)
    }

    @Test func thePromptShowsOnlyInsideTheWindow() {
        let (soon, now) = start(minutes: 5)
        #expect(MeetingPrompt.minutesUntil(start: soon, now: now) == 5)
        let (early, _) = start(minutes: 11)
        #expect(MeetingPrompt.minutesUntil(start: early, now: now, lead: 10) == nil)
        let (past, _) = start(minutes: -1)
        #expect(MeetingPrompt.minutesUntil(start: past, now: now) == nil)
    }

    @Test func theLineNamesTheMeetingAndTheMinutes() {
        #expect(MeetingPrompt.line(name: "Ada", minutes: 5) == "Your meeting with Ada starts in 5 min. See it?")
    }

    @Test func openingShowsPurposeContextPeopleAndJoin() {
        let detail = MeetingPrompt.detail(purpose: "Ship the prompt. https://example.com",
                                          context: "Last time: the agenda",
                                          attendees: [MeetingPrompt.Attendee(name: "Ada", role: "Design", company: "North")],
                                          callApp: "Meet", joinURL: "https://meet.example/abc",
                                          shared: false, presenting: false, captureKnown: true,
                                          expanded: true, contactsAllowed: true)
        #expect(detail.collapsed == false)
        #expect(detail.purpose == "Ship the prompt.")
        #expect(detail.context == "Last time: the agenda")
        #expect(detail.attendees.first?.role == "Design")
        #expect(detail.callApp == "Meet")
        #expect(detail.joinURL == "https://meet.example/abc")
    }

    @Test func aSharedScreenHidesTheDetailEvenAfterAClick() {
        let detail = MeetingPrompt.detail(purpose: "Secret", context: "Notes",
                                          attendees: [MeetingPrompt.Attendee(name: "Ada", role: "Design", company: "North")],
                                          callApp: "Meet", joinURL: "https://meet.example/abc",
                                          shared: true, presenting: false, captureKnown: true,
                                          expanded: true, contactsAllowed: true)
        #expect(detail.collapsed)
        #expect(detail.purpose.isEmpty)
        #expect(detail.context.isEmpty)
        #expect(detail.attendees.isEmpty)
        #expect(detail.joinURL == nil)
    }

    @Test func unknownCaptureStaysCollapsedUntilOpened() {
        let closed = MeetingPrompt.detail(purpose: "Agenda", context: "Prior", attendees: [],
                                          callApp: "Meet", joinURL: nil,
                                          shared: false, presenting: false, captureKnown: false,
                                          expanded: false, contactsAllowed: true)
        #expect(closed.collapsed)
        let open = MeetingPrompt.detail(purpose: "Agenda", context: "Prior", attendees: [],
                                        callApp: "Meet", joinURL: nil,
                                        shared: false, presenting: false, captureKnown: false,
                                        expanded: true, contactsAllowed: false)
        #expect(open.collapsed == false)
        #expect(open.purpose == "Agenda")
        #expect(open.joinURL == nil)
    }
}
