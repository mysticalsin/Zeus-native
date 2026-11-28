import Testing
@testable import ZeusCore

struct AwakeHoldDrawTests {
    private func cards(_ plan: AwakeHoldDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshSessionLeavesTheDisplayAlone() {
        let usual = AwakeHoldDraw.plan(screen: "Off", agents: "Off")
        #expect(cards(usual) == ["Hold", "Screen: Off", "Agents: Off"])
        #expect(AwakeHoldAsk.line(screen: "Off", agents: "Off") == "A session leaves the display alone, and agents do not keep the Mac awake.")
        #expect(usual.boltCaption(at: 0) == "Hold")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Agents: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(AwakeHoldAsk.line(screen: "On", agents: "On") == "A session keeps the display awake, and agents keep the Mac awake.")
        #expect(AwakeHoldAsk.line(screen: "On", agents: "Off") == "A session keeps the display awake, and agents do not keep the Mac awake.")
        #expect(cards(AwakeHoldDraw.plan(screen: "Yes", agents: "Off")) == ["Hold", "Can't"])
        #expect(AwakeHoldAsk.line(screen: "Off", agents: "Maybe") == "I can't read the keep awake options.")
    }

    @Test func theSessionLengthStaysOffThisAsk() {
        #expect(AwakeHoldAsk.matches("does a session keep the display awake"))
        #expect(AwakeHoldAsk.matches("Hey Zeus, do agents keep the Mac awake?"))
        #expect(AwakeHoldAsk.matches("how are keep awake options set"))
        #expect(!AwakeHoldAsk.matches("how is keep awake set"))
        #expect(!AwakeHoldAsk.matches("which battery floor"))
        #expect(!AwakeHoldAsk.matches("what is on day to day"))
        #expect(!AwakeHoldAsk.matches("what is the polyglot key"))
    }
}
