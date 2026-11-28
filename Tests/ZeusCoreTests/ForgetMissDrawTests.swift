import Testing
@testable import ZeusCore

struct ForgetMissDrawTests {
    @Test func aMissingMemoryShowsNone() throws {
        let plan = try #require(ForgetMissDraw.from(line: "I didn't find that."))
        func cards(_ plan: ForgetMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Forget", "None"])
        #expect(plan.boltCaption(at: 0) == "Forget")
        #expect(plan.boltCaption(at: 100) == "None")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aForgottenItemAndARunningTimerAreNotThisMiss() {
        #expect(ForgetMissDraw.from(line: "") == nil)
        #expect(ForgetMissDraw.from(line: "I didn't find that") == nil)
        #expect(ForgetMissDraw.from(line: "Forgot one item.") == nil)
        #expect(ForgetMissDraw.from(line: "Which one should I forget?") == nil)
        #expect(ForgetMissDraw.from(line: "No timer is running.") == nil)
        #expect(ForgetMissDraw.from(line: "No field called \"Search\"") == nil)
    }
}
