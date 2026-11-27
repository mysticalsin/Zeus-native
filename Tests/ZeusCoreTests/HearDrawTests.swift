import Testing
@testable import ZeusCore

struct HearDrawTests {
    @Test func theHearingNoticeShowsAccess() throws {
        let notice = "I can't hear you yet. Check that Zeus has microphone and speech recognition access."
        let plan = try #require(HearDraw.from(message: notice))
        func cards(_ plan: HearDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Hear", "Access"])
        #expect(plan.boltCaption(at: 0) == "Hear")
        #expect(plan.boltCaption(at: 100) == "Access")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherSentencesAreNotTheHearingNotice() {
        #expect(HearDraw.from(message: "") == nil)
        #expect(HearDraw.from(message: "I can't see your screen yet.") == nil)
        #expect(HearDraw.from(message: "The AI failed; try again.") == nil)
        #expect(HearDraw.from(message: "Zeus can't hear you: allow the microphone") == nil)
    }
}
