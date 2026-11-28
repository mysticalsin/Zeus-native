import Testing
@testable import ZeusCore

struct SendSkipDrawTests {
    @Test func aPromptLeftUnsentShowsNo() throws {
        let plan = try #require(SendSkipDraw.from(line: SendSkipDraw.line))
        func cards(_ plan: SendSkipDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Send", "No"])
        #expect(plan.boltCaption(at: 0) == "Send")
        #expect(plan.boltCaption(at: 100) == "No")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func typingAndOtherRefusalsAreNotASend() {
        #expect(SendSkipDraw.from(line: "") == nil)
        #expect(SendSkipDraw.from(line: "Okay, I didn't type anything.") == nil)
        #expect(SendSkipDraw.from(line: "Okay, I left it.") == nil)
        #expect(SendSkipDraw.from(line: "Okay, I left it open.") == nil)
        #expect(SendSkipDraw.from(line: "Okay, I won't run it.") == nil)
    }
}
