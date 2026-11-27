import Testing
@testable import ZeusCore

struct TourStopDrawTests {
    @Test func aStoppedTourShowsStopped() throws {
        let plan = try #require(TourStopDraw.from(line: "Okay, tour stopped."))
        func cards(_ plan: TourStopDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Tour", "Stopped"])
        #expect(plan.boltCaption(at: 0) == "Tour")
        #expect(plan.boltCaption(at: 100) == "Stopped")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aFinishedTourAndAnEarlyBrowserStopAreNotThisCard() {
        #expect(TourStopDraw.from(line: "") == nil)
        #expect(TourStopDraw.from(line: "That's it, you're done.") == nil)
        #expect(TourStopDraw.from(line: "I couldn't put that tour together.") == nil)
        #expect(TourStopDraw.from(line: "you stopped it before it began.") == nil)
    }
}
