import Testing
@testable import ZeusCore

struct FullerAnswerDrawTests {
    @Test func aSentenceFollowsFuller() throws {
        let plan = try #require(FullerAnswerDraw.plan(sentence: "The tides are high."))
        func cards(_ plan: FullerAnswerDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Fuller", "The tides are high."])
        #expect(plan.boltCaption(at: 0) == "Fuller")
        #expect(plan.boltCaption(at: 100) == "The tides are high.")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankSentenceDrawsFullerAlone() throws {
        let blank = try #require(FullerAnswerDraw.plan(sentence: " "))
        func cards(_ plan: FullerAnswerDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(blank) == ["Fuller"])
        #expect(blank.sentence.isEmpty)
        #expect(blank.boltCaption(at: 100) == "Fuller")
    }
}
