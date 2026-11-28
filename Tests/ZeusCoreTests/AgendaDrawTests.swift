import Testing
@testable import ZeusCore

struct AgendaDrawTests {
    private func cards(_ plan: AgendaDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func oneEventDrawsTheTitleThenTheTime() {
        let plan = AgendaDraw.plan(count: 1, title: "Lunch", when: "1:00 PM", allDay: false)
        #expect(plan.map(cards) == ["Agenda", "Lunch", "1:00 PM"])
        #expect(AgendaAsk.line(count: 1, title: "Lunch", when: "1:00 PM", allDay: false) == "You have Lunch at 1:00 PM.")
        #expect(AgendaAsk.line(count: 1, title: "Holiday", when: "", allDay: true) == "You have Holiday, all day.")
        #expect(AgendaDraw.plan(count: 1, title: "Holiday", when: "", allDay: true).map(cards) == ["Agenda", "Holiday", "All day"])
        #expect(plan?.boltCaption(at: 0) == "Agenda")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Lunch")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "1:00 PM")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(AgendaDraw.plan(count: 0, title: "Lunch", when: "1:00 PM", allDay: false) == nil)
        #expect(AgendaDraw.plan(count: 1, title: "  ", when: "1:00 PM", allDay: false) == nil)
    }

    @Test func severalEventsDrawTheCountAndAClearAgendaIsNotWhatsNext() {
        let plan = AgendaDraw.plan(count: 3, title: "Standup", when: "9:00 AM", allDay: false)
        #expect(plan.map(cards) == ["Agenda", "3 left", "Standup"])
        #expect(AgendaAsk.line(count: 3, title: "Standup", when: "9:00 AM", allDay: false) == "You have 3 events left. Next is Standup.")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "3 left")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Standup")
        #expect(cards(AgendaDraw.clear()) == ["Agenda", "Clear"])
        #expect(cards(AgendaDraw.access()) == ["Agenda", "Access"])
        #expect(AgendaAsk.clear == "The agenda is clear.")
        #expect(AgendaAsk.access == "I need Calendar access to read the agenda.")
        #expect(AgendaAsk.matches("what's on my agenda"))
        #expect(AgendaAsk.matches("Hey Zeus, how many meetings left?"))
        #expect(AgendaAsk.matches("what's coming up"))
        #expect(!AgendaAsk.matches("what's next"))
        #expect(!AgendaAsk.matches("what do I have today"))
        #expect(!AgendaAsk.matches("join my next meeting"))
        #expect(!AgendaAsk.matches("how many to-dos"))
        #expect(!AgendaAsk.matches("how many notifications"))
        #expect(!AgendaAsk.matches("how many days left"))
    }
}
