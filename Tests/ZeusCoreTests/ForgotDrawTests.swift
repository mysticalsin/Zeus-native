import Testing
@testable import ZeusCore

struct ForgotDrawTests {
    @Test func oneForgottenItemShowsOne() throws {
        let plan = try #require(ForgotDraw.from(line: "Forgot one item."))
        func cards(_ plan: ForgotDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Forgot", "One"])
        #expect(plan.boltCaption(at: 0) == "Forgot")
        #expect(plan.boltCaption(at: 100) == "One")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aMissingMemoryAndABlankLineAreNotThisForget() {
        #expect(ForgotDraw.from(line: "") == nil)
        #expect(ForgotDraw.from(line: "Forgot one item") == nil)
        #expect(ForgotDraw.from(line: "I didn't find that.") == nil)
        #expect(ForgotDraw.from(line: "Which one should I forget?") == nil)
        #expect(ForgotDraw.from(line: "Got it. I'll remember that.") == nil)
        #expect(ForgotDraw.from(line: "No timer is running.") == nil)
    }
}
