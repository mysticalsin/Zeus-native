import Testing
@testable import ZeusCore

struct PresentStepsDrawTests {
    @Test func aStepsCardBuildsEachStep() throws {
        let plan = try #require(PresentStepsDraw.plan(lines: ["Export", "Open File", "Pick format"]))
        func cards(_ plan: PresentStepsDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Export", "Open File", "Pick format"])
        #expect(plan.boltCaption(at: 0) == "Export")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Open File")
        #expect(plan.boltCaption(at: 100) == "Pick format")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankCardIsNotDrawnAndASixthStepStaysOff() throws {
        #expect(PresentStepsDraw.plan(lines: []) == nil)
        #expect(PresentStepsDraw.plan(lines: [" ", "\n"]) == nil)
        let plan = try #require(PresentStepsDraw.plan(lines: ["One", "Two", "Three", "Four", "Five", "Six"]))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["One", "Two", "Three", "Four", "Five"])
        #expect(plan.boltCaption(at: 100) == "Five")
    }
}
