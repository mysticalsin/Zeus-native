import Testing
@testable import ZeusCore

struct TabOpenDrawTests {
    @Test func aTabLeftOpenShowsOpen() throws {
        let plan = try #require(TabOpenDraw.from(line: "Okay, I left it open."))
        func cards(_ plan: TabOpenDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Tab", "Open"])
        #expect(plan.boltCaption(at: 0) == "Tab")
        #expect(plan.boltCaption(at: 100) == "Open")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aClickLeftAloneAndASendSkipAreNotThisCard() {
        #expect(TabOpenDraw.from(line: "") == nil)
        #expect(TabOpenDraw.from(line: "Okay, I left it.") == nil)
        #expect(TabOpenDraw.from(line: "Okay, I won't send it.") == nil)
        #expect(TabOpenDraw.from(line: "Okay, I didn't type anything.") == nil)
        #expect(TabOpenDraw.from(line: "Zeus isn't ready yet.") == nil)
    }
}
