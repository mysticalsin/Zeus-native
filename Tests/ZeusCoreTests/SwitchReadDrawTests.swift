import Testing
@testable import ZeusCore

struct SwitchReadDrawTests {
    @Test func aSwitchZeusCouldNotReadShowsUnknown() throws {
        let plan = try #require(SwitchReadDraw.from(line: "I can't tell whether Dark Mode is on or off."))
        func cards(_ plan: SwitchReadDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Switch", "Unknown"])
        #expect(plan.boltCaption(at: 0) == "Switch")
        #expect(plan.boltCaption(at: 100) == "Unknown")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aScrollAndAnUnreadPageListAreNotThisSwitch() {
        #expect(SwitchReadDraw.from(line: "") == nil)
        #expect(SwitchReadDraw.from(line: "I can't tell whether is on or off.") == nil)
        #expect(SwitchReadDraw.from(line: "That scroll amount is out of range.") == nil)
        #expect(SwitchReadDraw.from(line: "The separate browser's page list couldn't be read.") == nil)
        #expect(SwitchReadDraw.from(line: "I don't know the key return.") == nil)
        #expect(SwitchReadDraw.from(line: "Safari isn't open.") == nil)
    }
}
