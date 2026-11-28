import Testing
@testable import ZeusCore

@Suite struct LocalAnswerDrawTests {
    @Test func aLocalAnswerIsDrawnAsAShortCard() throws {
        let answer = "Canberra. A planned city between Sydney and Melbourne, still standing."
        let plan = try #require(LocalAnswerDraw.plan(answer: answer))
        #expect(plan.bolt == "Canberra. A planned city between Sydney")
        #expect(plan.bolt.count <= LocalAnswerDraw.boltLimit)
        #expect(answer.hasPrefix(plan.bolt))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == [plan.bolt])
        #expect(plan.guide == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.draw.marks.contains { mark in
            if case .ring = mark.shape { return true }
            return false
        })
    }

    @Test func anEmptyLocalAnswerIsNotDrawn() {
        #expect(LocalAnswerDraw.plan(answer: "   ") == nil)
        #expect(LocalAnswerDraw.plan(answer: "") == nil)
    }
}
