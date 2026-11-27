import Testing
@testable import ZeusCore

struct ScreenSightDrawTests {
    @Test func theScreenNoticeShowsNotOn() throws {
        let notice = ScreenSightDraw.lead + " Turn on Screen Recording for Zeus."
        let plan = try #require(ScreenSightDraw.from(message: notice))
        func cards(_ plan: ScreenSightDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(notice.hasPrefix(ScreenSightDraw.lead))
        #expect(cards(plan) == ["Screen", "Not on"])
        #expect(plan.boltCaption(at: 0) == "Screen")
        #expect(plan.boltCaption(at: 100) == "Not on")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherSentencesAreNotTheScreenNotice() {
        #expect(ScreenSightDraw.from(message: "") == nil)
        #expect(ScreenSightDraw.from(message: "I can't hear you yet.") == nil)
        #expect(ScreenSightDraw.from(message: "Screen Recording is off") == nil)
    }
}
