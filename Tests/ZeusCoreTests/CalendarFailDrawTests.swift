import Testing
@testable import ZeusCore

struct CalendarFailDrawTests {
    @Test func aCalendarThatCannotTakeAnEventShowsWhy() throws {
        let empty = try #require(CalendarFailDraw.from(line: "No calendar accepts new events. Add one in Calendar."))
        let unsaved = try #require(CalendarFailDraw.from(line: "The calendar wouldn't save that event."))
        let gone = try #require(CalendarFailDraw.from(line: "Calendar isn't available."))
        func cards(_ plan: CalendarFailDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(empty) == ["Calendar", "None"])
        #expect(empty.boltCaption(at: 0) == "Calendar")
        #expect(empty.boltCaption(at: 100) == "None")
        #expect(empty.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(empty.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(unsaved) == ["Calendar", "Not saved"])
        #expect(cards(gone) == ["Calendar", "Unavailable"])
    }

    @Test func aMissingCalendarPermissionIsNotThisFailure() {
        #expect(CalendarFailDraw.from(line: "") == nil)
        #expect(CalendarFailDraw.from(line: "I need Calendar access to add that.") == nil)
        #expect(CalendarFailDraw.from(line: "Added lunch to your calendar.") == nil)
        #expect(CalendarFailDraw.from(line: "Beamer isn't running. Say start Beamer first.") == nil)
    }
}
