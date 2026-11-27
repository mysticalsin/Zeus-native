import Testing
@testable import ZeusCore

struct TourDoneDrawTests {
    @Test func aFinishedTourShowsDone() throws {
        let plan = try #require(TourDoneDraw.from(line: "That's it, you're done."))
        func cards(_ plan: TourDoneDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Tour", "Done"])
        #expect(plan.boltCaption(at: 0) == "Tour")
        #expect(plan.boltCaption(at: 100) == "Done")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankLineAndOtherToursAreNotDone() {
        #expect(TourDoneDraw.from(line: "") == nil)
        #expect(TourDoneDraw.from(line: "Okay, tour stopped.") == nil)
        #expect(TourDoneDraw.from(line: "I couldn't put that tour together.") == nil)
        #expect(TourDoneDraw.from(line: "I'm stuck: the login form.") == nil)
    }
}
