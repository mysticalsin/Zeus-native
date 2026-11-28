import Testing
@testable import ZeusCore

struct CalendarEventDrawTests {
    @Test func anEventShowsTheTitleThenTheTime() throws {
        let plan = try #require(CalendarEventDraw.plan(title: "Lunch with Ana", when: "1:00 PM"))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Calendar", "Lunch with Ana", "1:00 PM"])
        #expect(plan.boltCaption(at: 0) == "Calendar")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Lunch with Ana")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "1:00 PM")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
    }

    @Test func aBlankTitleIsNotDrawnAndABlankTimeIsOmitted() throws {
        #expect(CalendarEventDraw.plan(title: "  ", when: "1:00 PM") == nil)
        #expect(CalendarEventDraw.plan(title: "\n", when: "All day") == nil)
        let plan = try #require(CalendarEventDraw.plan(title: "Dentist", when: "  "))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Calendar", "Dentist"])
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 3) == "Dentist")
    }
}
