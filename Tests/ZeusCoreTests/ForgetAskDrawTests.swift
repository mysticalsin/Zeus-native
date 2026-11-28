import Testing
@testable import ZeusCore

struct ForgetAskDrawTests {
    @Test func severalMemoriesAskWhich() throws {
        let plan = try #require(ForgetAskDraw.from(line: "That matches 2 things: \"tea\", \"coffee\". Which one should I forget? Say it more exactly."))
        func cards(_ plan: ForgetAskDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Forget", "Which"])
        #expect(plan.boltCaption(at: 0) == "Forget")
        #expect(plan.boltCaption(at: 100) == "Which")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aMissingMemoryAndASwitchAreNotThisAsk() {
        #expect(ForgetAskDraw.from(line: "") == nil)
        #expect(ForgetAskDraw.from(line: "That matches Which one should I forget? Say it more exactly.") == nil)
        #expect(ForgetAskDraw.from(line: "Forgot one item.") == nil)
        #expect(ForgetAskDraw.from(line: "I didn't find that.") == nil)
        #expect(ForgetAskDraw.from(line: "I couldn't save that, so nothing changed.") == nil)
        #expect(ForgetAskDraw.from(line: "I can't tell whether Dark Mode is on or off.") == nil)
        #expect(ForgetAskDraw.from(line: "Did you mean Safari or Chrome?") == nil)
    }
}
