import Testing
@testable import ZeusCore

struct CalendarPageDrawTests {
    private func cards(_ plan: CalendarPageDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePickedDayAndTheEventPanel() {
        let usual = CalendarPageDraw.plan(day: "Today", panel: "Closed")
        #expect(cards(usual) == ["Day", "Day: Today", "Event: Closed"])
        #expect(CalendarPageAsk.line(day: "Today", panel: "Closed") == "The calendar is on today, and no event is open.")
        #expect(usual.boltCaption(at: 0) == "Day")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Event: Closed")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(CalendarPageAsk.line(day: "Other", panel: "Open") == "The calendar is on another day, and an event is open.")
        #expect(CalendarPageAsk.line(day: "Today", panel: "Open") == "The calendar is on today, and an event is open.")
        #expect(cards(CalendarPageDraw.plan(day: "Tomorrow", panel: "Closed")) == ["Day", "Can't"])
        #expect(CalendarPageAsk.line(day: "Today", panel: "Maybe") == "I can't read the calendar page.")
    }

    @Test func theNextEventStaysOffThisAsk() {
        #expect(CalendarPageAsk.matches("is the calendar on today"))
        #expect(CalendarPageAsk.matches("Hey Zeus, is a calendar event open?"))
        #expect(CalendarPageAsk.matches("which day is the calendar showing"))
        #expect(!CalendarPageAsk.matches("what is my next event"))
        #expect(!CalendarPageAsk.matches("what is my agenda"))
        #expect(!CalendarPageAsk.matches("is chat history showing"))
        #expect(!CalendarPageAsk.matches("is memory learning on"))
    }
}
