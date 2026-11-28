import Testing
@testable import ZeusCore

struct AskLeftDrawTests {
    @Test func aStartZeusCouldNotAskAboutShowsLeft() throws {
        let plan = try #require(AskLeftDraw.from(line: "I can't ask you about that yet, so I left."))
        func cards(_ plan: AskLeftDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Ask", "Left"])
        #expect(plan.boltCaption(at: 0) == "Ask")
        #expect(plan.boltCaption(at: 100) == "Left")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aDeclinedStartAndASilentMenuAreNotThisAsk() {
        #expect(AskLeftDraw.from(line: "") == nil)
        #expect(AskLeftDraw.from(line: "I can't ask you about that yet, so I left it.") == nil)
        #expect(AskLeftDraw.from(line: "I can't ask you about that command yet, so I.") == nil)
        #expect(AskLeftDraw.from(line: "Okay, I won't start it.") == nil)
        #expect(AskLeftDraw.from(line: "Okay, I won't run it.") == nil)
        #expect(AskLeftDraw.from(line: "Beamer's menu didn't respond to \u{201C}Pause\u{201D}.") == nil)
        #expect(AskLeftDraw.from(line: "Spotify is showing tides, but I couldn't press play.") == nil)
    }
}
