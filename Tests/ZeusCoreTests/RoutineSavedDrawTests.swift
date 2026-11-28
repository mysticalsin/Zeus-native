import Testing
@testable import ZeusCore

struct RoutineSavedDrawTests {
    @Test func aSavedRoutineShowsTheNameThenTheTime() throws {
        #expect(RoutineSavedDraw.whenLine(daily: false, hour: 8) == "Weekdays at 8 AM")
        #expect(RoutineSavedDraw.whenLine(daily: true, hour: 15) == "Every day at 3 PM")
        #expect(RoutineSavedDraw.whenLine(daily: true, hour: 0) == "Every day at 12 AM")
        #expect(RoutineSavedDraw.whenLine(daily: false, hour: 12) == "Weekdays at 12 PM")
        let plan = try #require(RoutineSavedDraw.plan(name: "Summarize my calendar", when: "Weekdays at 8 AM"))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Routine", "Summarize my calendar", "Weekdays at 8 AM"])
        #expect(plan.boltCaption(at: 0) == "Routine")
        #expect(plan.boltCaption(at: 100) == "Weekdays at 8 AM")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankNameIsNotDrawnAndABlankTimeIsOmitted() throws {
        #expect(RoutineSavedDraw.plan(name: "  ", when: "Weekdays at 8 AM") == nil)
        let plan = try #require(RoutineSavedDraw.plan(name: "Morning note", when: " "))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Routine", "Morning note"])
        #expect(plan.boltCaption(at: 100) == "Morning note")
    }
}
