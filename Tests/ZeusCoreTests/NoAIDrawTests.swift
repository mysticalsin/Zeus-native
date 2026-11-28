import Testing
@testable import ZeusCore

struct NoAIDrawTests {
    @Test func noConnectedAIShowsConnect() throws {
        let plan = try #require(NoAIDraw.from(line: "no AI is connected. Connect one in Settings, Integrations."))
        func cards(_ plan: NoAIDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Browser", "Connect"])
        #expect(plan.boltCaption(at: 0) == "Browser")
        #expect(plan.boltCaption(at: 100) == "Connect")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anAnswerFailureAndAMemoryMissAreNotThisCard() {
        #expect(NoAIDraw.from(line: "") == nil)
        #expect(NoAIDraw.from(line: "That AI isn't signed in; check Settings.") == nil)
        #expect(NoAIDraw.from(line: "Every AI is out of quota; instant commands still work.") == nil)
        #expect(NoAIDraw.from(line: "I couldn't save that, so nothing changed.") == nil)
    }
}
