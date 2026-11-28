import Testing
@testable import ZeusCore

struct TypeSkipDrawTests {
    @Test func typingLeftUndoneShowsNo() throws {
        let plan = try #require(TypeSkipDraw.from(line: TypeSkipDraw.line))
        func cards(_ plan: TypeSkipDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Type", "No"])
        #expect(plan.boltCaption(at: 0) == "Type")
        #expect(plan.boltCaption(at: 100) == "No")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherRefusalsAreNotTyping() {
        #expect(TypeSkipDraw.from(line: "") == nil)
        #expect(TypeSkipDraw.from(line: "Okay, I left it.") == nil)
        #expect(TypeSkipDraw.from(line: "Okay, I won't send it.") == nil)
        #expect(TypeSkipDraw.from(line: "I couldn't make sense of that browser step.") == nil)
        #expect(TypeSkipDraw.from(line: "Okay, I won't run it.") == nil)
    }
}
