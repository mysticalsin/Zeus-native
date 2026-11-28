import Testing
@testable import ZeusCore

struct AnswerFailDrawTests {
    @Test func eachSpokenFailureNamesItsReason() throws {
        let quota = try #require(AnswerFailDraw.from(message: "Every AI is out of quota; instant commands still work."))
        let signedOut = try #require(AnswerFailDraw.from(message: "That AI isn't signed in; check Settings."))
        let late = try #require(AnswerFailDraw.from(message: "No AI answered in time; try again."))
        let offline = try #require(AnswerFailDraw.from(message: "I couldn't reach Claude; check your connection."))
        let failed = try #require(AnswerFailDraw.from(message: "The AI failed; try again."))
        func cards(_ plan: AnswerFailDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(quota) == ["AI", "Quota"])
        #expect(cards(signedOut) == ["AI", "Sign in"])
        #expect(cards(late) == ["AI", "No answer"])
        #expect(cards(offline) == ["AI", "Offline"])
        #expect(cards(failed) == ["AI", "Failed"])
        #expect(quota.boltCaption(at: 0) == "AI")
        #expect(quota.boltCaption(at: 100) == "Quota")
        #expect(quota.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(quota.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherSentencesAreNotAnAnswerFailure() {
        #expect(AnswerFailDraw.from(message: "") == nil)
        #expect(AnswerFailDraw.from(message: "I can't see your screen yet.") == nil)
        #expect(AnswerFailDraw.from(message: "I can't hear you yet.") == nil)
        #expect(AnswerFailDraw.from(message: "The AI failed") == nil)
    }
}
