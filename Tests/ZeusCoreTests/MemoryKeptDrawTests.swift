import Testing
@testable import ZeusCore

struct MemoryKeptDrawTests {
    @Test func aKeptFactIsDrawnAfterRemembered() throws {
        let plan = try #require(MemoryKeptDraw.plan(fact: "I take tea at 4"))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Remembered", "I take tea at 4"])
        #expect(plan.boltCaption(at: 0) == "Remembered")
        #expect(plan.boltCaption(at: 100) == "I take tea at 4")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aSecretIsNotDrawnAndARefusalShowsNoFact() {
        #expect(MemoryKeptDraw.plan(fact: "  ") == nil)
        #expect(MemoryKeptDraw.plan(fact: "the password is swordfish") == nil)
        #expect(MemoryKeptDraw.plan(fact: "card cvv 123") == nil)
        #expect(MemoryKeptDraw.plan(fact: "social security number") == nil)
        let refused = MemoryKeptDraw.refused()
        let cards = refused.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Not stored"])
        #expect(refused.fact.isEmpty)
        #expect(refused.boltCaption(at: 100) == "Not stored")
    }
}
