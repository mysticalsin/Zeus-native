import Testing
@testable import ZeusCore

@Suite("Meeting poll due")
struct MeetingPollDueTests {
    @Test func theGapIsSevenTenthsOfASecond() {
        #expect(MeetingPollDue.interval == 0.7)
    }

    @Test func aFreshClockIsDueAndAShortGapIsNot() {
        #expect(MeetingPollDue.isDue(now: 0, last: -.infinity))
        #expect(!MeetingPollDue.isDue(now: 0, last: 0))
        #expect(!MeetingPollDue.isDue(now: 0.699, last: 0))
        #expect(MeetingPollDue.isDue(now: 1, last: 0))
    }

    @Test func theBoundaryAndABackwardsClockAreDue() {
        #expect(MeetingPollDue.isDue(now: 0.7, last: 0))
        #expect(MeetingPollDue.isDue(now: 4, last: 5))
    }
}
