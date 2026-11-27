import Testing
@testable import ZeusCore

struct EarlyStopDrawTests {
    @Test func aStopBeforeTheStartShowsBefore() throws {
        let plan = try #require(EarlyStopDraw.from(line: "you stopped it before it began."))
        func cards(_ plan: EarlyStopDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Stop", "Before"])
        #expect(plan.boltCaption(at: 0) == "Stop")
        #expect(plan.boltCaption(at: 100) == "Before")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aTourStopAndAnEmptyAskAreNotThisCard() {
        #expect(EarlyStopDraw.from(line: "") == nil)
        #expect(EarlyStopDraw.from(line: "Stopped.") == nil)
        #expect(EarlyStopDraw.from(line: "Okay, tour stopped.") == nil)
        #expect(EarlyStopDraw.from(line: "What should I look into?") == nil)
        #expect(EarlyStopDraw.from(line: "no AI is connected. Connect one in Settings, Integrations.") == nil)
    }
}
