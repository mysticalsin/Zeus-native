import Testing
@testable import ZeusCore

struct CalendarAccessDrawTests {
    @Test func aMissingCalendarGrantShowsAccess() throws {
        let plan = try #require(CalendarAccessDraw.from(line: CalendarAccessDraw.line))
        func cards(_ plan: CalendarAccessDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Calendar", "Access"])
        #expect(plan.boltCaption(at: 0) == "Calendar")
        #expect(plan.boltCaption(at: 100) == "Access")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anAddedEventIsNotTheGrant() {
        #expect(CalendarAccessDraw.from(line: "") == nil)
        #expect(CalendarAccessDraw.from(line: "Added lunch to your calendar.") == nil)
        #expect(CalendarAccessDraw.from(line: "Zeus needs Calendar access to add events.") == nil)
        #expect(CalendarAccessDraw.from(line: "I need Accessibility access to drive your Mac.") == nil)
    }
}
