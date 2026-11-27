import Testing
@testable import ZeusCore

struct TourFailDrawTests {
    @Test func aTourThatWillNotBuildShowsCant() throws {
        let plan = try #require(TourFailDraw.from(line: TourFailDraw.line))
        func cards(_ plan: TourFailDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Tour", "Can't"])
        #expect(plan.boltCaption(at: 0) == "Tour")
        #expect(plan.boltCaption(at: 100) == "Can't")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aWalkingTourAndOtherLinesAreNotThisCard() {
        #expect(TourFailDraw.from(line: "") == nil)
        #expect(TourFailDraw.from(line: "I couldn't find a project called Zeus.") == nil)
        #expect(TourFailDraw.from(line: "Okay, I won't start it.") == nil)
        #expect(TourFailDraw.from(line: "I couldn't find that on screen, so I'll keep going.") == nil)
    }
}
