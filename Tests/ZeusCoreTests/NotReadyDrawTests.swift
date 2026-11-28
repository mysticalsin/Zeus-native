import Testing
@testable import ZeusCore

struct NotReadyDrawTests {
    @Test func zeusNotReadyShowsNotReady() throws {
        let plan = try #require(NotReadyDraw.from(line: "Zeus isn't ready yet."))
        func cards(_ plan: NotReadyDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Zeus", "Not ready"])
        #expect(plan.boltCaption(at: 0) == "Zeus")
        #expect(plan.boltCaption(at: 100) == "Not ready")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aStoppedTourAndAMissingAIAreNotThisCard() {
        #expect(NotReadyDraw.from(line: "") == nil)
        #expect(NotReadyDraw.from(line: "Okay, tour stopped.") == nil)
        #expect(NotReadyDraw.from(line: "you stopped it before it began.") == nil)
        #expect(NotReadyDraw.from(line: "no AI is connected. Connect one in Settings, Integrations.") == nil)
    }
}
