import Testing
@testable import ZeusCore

struct KeepAwakeSetupDrawTests {
    private func cards(_ plan: KeepAwakeSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func lengthFloorAndHeatFollowLimits() {
        let usual = KeepAwakeSetupDraw.plan(length: "30 minutes", floor: "10%", heat: "On")
        #expect(cards(usual) == ["Limits", "Length: 30 minutes", "Floor: 10%", "Heat: On"])
        #expect(KeepAwakeSetupAsk.line(length: "30 minutes", floor: "10%", heat: "On") == "Keep awake runs for 30 minutes, ends below 10%, and stops when the Mac gets too hot.")
        #expect(usual.boltCaption(at: 0) == "Limits")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Heat: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(KeepAwakeSetupAsk.line(length: "Indefinitely", floor: "Off", heat: "Off") == "Keep awake runs for Indefinitely, has no battery floor, and stays up when the Mac gets hot.")
        #expect(cards(KeepAwakeSetupDraw.plan(length: "45 minutes", floor: "10%", heat: "On")) == ["Limits", "Can't"])
        #expect(KeepAwakeSetupAsk.line(length: "30 minutes", floor: "12%", heat: "Maybe") == "I can't read how keep awake is set.")
    }

    @Test func startingASessionStaysOffThisAsk() {
        #expect(KeepAwakeSetupAsk.matches("how's keep awake set"))
        #expect(KeepAwakeSetupAsk.matches("Hey Zeus, which battery floor?"))
        #expect(KeepAwakeSetupAsk.matches("keep awake settings"))
        #expect(!KeepAwakeSetupAsk.matches("keep awake"))
        #expect(!KeepAwakeSetupAsk.matches("how's polyglot set"))
        #expect(!KeepAwakeSetupAsk.matches("how's the heat"))
        #expect(!KeepAwakeSetupAsk.matches("what's on day to day"))
    }
}
