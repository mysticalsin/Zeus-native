import Testing
@testable import ZeusCore

struct RunUnclearDrawTests {
    @Test func anUnclearRunShowsUnclear() throws {
        let plan = try #require(RunUnclearDraw.from(line: RunUnclearDraw.line))
        func cards(_ plan: RunUnclearDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Command", "Unclear"])
        #expect(plan.boltCaption(at: 0) == "Command")
        #expect(plan.boltCaption(at: 100) == "Unclear")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlockedOrDeclinedRunIsNotUnclear() {
        #expect(RunUnclearDraw.from(line: "") == nil)
        #expect(RunUnclearDraw.from(line: "Okay, I won't run it.") == nil)
        #expect(RunUnclearDraw.from(line: "rm is blocked") == nil)
        #expect(RunUnclearDraw.from(line: "I couldn't put that tour together.") == nil)
        #expect(RunUnclearDraw.from(line: "I couldn't add that to-do.") == nil)
    }
}
