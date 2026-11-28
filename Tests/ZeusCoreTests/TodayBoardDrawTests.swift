import Testing
@testable import ZeusCore

struct TodayBoardDrawTests {
    @Test func aClearDayShowsClearAndNoToDos() {
        #expect(TodayBoardDraw.eventLine(count: 0, first: nil) == "Clear")
        #expect(TodayBoardDraw.todoLine(count: 0, overdue: 2, first: nil) == "No to-dos")
        #expect(TodayBoardDraw.meetingLine(count: 0, first: "Standup") == nil)
        let plan = TodayBoardDraw.plan(events: "Clear", todos: "No to-dos", meetings: nil, weather: nil)
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Today", "Clear", "No to-dos"])
        #expect(plan.boltCaption(at: 0) == "Today")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Clear")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
    }

    @Test func oneEventKeepsItsNameAndOverdueReplacesTheList() {
        #expect(TodayBoardDraw.eventLine(count: 1, first: "Lunch at 1:00 PM") == "Lunch at 1:00 PM")
        #expect(TodayBoardDraw.eventLine(count: 4, first: "Lunch") == "4 events")
        #expect(TodayBoardDraw.todoLine(count: 3, overdue: 1, first: "Call Ana") == "1 overdue")
        #expect(TodayBoardDraw.meetingLine(count: 2, first: "Standup") == "2 meetings")
        let plan = TodayBoardDraw.plan(events: "Lunch at 1:00 PM", todos: "1 overdue", meetings: nil,
                                       weather: "It's 72 degrees, high of 80.")
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Today", "Lunch at 1:00 PM", "1 overdue", "It's 72 degrees, high of 80."])
        #expect(plan.boltCaption(at: 100) == "It's 72 degrees, high of 80.")
    }
}
