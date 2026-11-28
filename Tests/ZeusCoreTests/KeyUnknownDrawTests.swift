import Testing
@testable import ZeusCore

struct KeyUnknownDrawTests {
    @Test func anUnknownKeyShowsUnknown() throws {
        let plan = try #require(KeyUnknownDraw.from(line: "I don't know the key return."))
        func cards(_ plan: KeyUnknownDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Key", "Unknown"])
        #expect(plan.boltCaption(at: 0) == "Key")
        #expect(plan.boltCaption(at: 100) == "Unknown")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aSwitchAndAStoppedBrowserAreNotThisKey() {
        #expect(KeyUnknownDraw.from(line: "") == nil)
        #expect(KeyUnknownDraw.from(line: "I don't know the key.") == nil)
        #expect(KeyUnknownDraw.from(line: "I don't know the key .") == nil)
        #expect(KeyUnknownDraw.from(line: "I can't tell whether Dark Mode is on or off.") == nil)
        #expect(KeyUnknownDraw.from(line: "That scroll amount is out of range.") == nil)
        #expect(KeyUnknownDraw.from(line: "The separate browser stopped.") == nil)
        #expect(KeyUnknownDraw.from(line: "I can't expand Dark Mode.") == nil)
    }
}
