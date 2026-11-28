import Testing
@testable import ZeusCore

struct InsomniaSetupDrawTests {
    private func cards(_ plan: InsomniaSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func lidMuteAndPowerFollowSleep() {
        let usual = InsomniaSetupDraw.plan(lid: "On", mute: "On", power: "On")
        #expect(cards(usual) == ["Sleep", "Lid: On", "Mute: On", "Power: On"])
        #expect(InsomniaSetupAsk.line(lid: "On", mute: "On", power: "On") == "Lid-closed mode is on, mute on close is on, and Low Power Mode is on.")
        #expect(usual.boltCaption(at: 0) == "Sleep")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Power: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(InsomniaSetupAsk.line(lid: "Off", mute: "Off", power: "Off") == "Lid-closed mode is off, mute on close is off, and Low Power Mode is off.")
        #expect(cards(InsomniaSetupDraw.plan(lid: "Maybe", mute: "On", power: "On")) == ["Sleep", "Can't"])
        #expect(InsomniaSetupAsk.line(lid: "On", mute: "Loud", power: "On") == "I can't read how Insomnia is set.")
    }

    @Test func theLiveLidStaysOffThisAsk() {
        #expect(InsomniaSetupAsk.matches("how's insomnia set"))
        #expect(InsomniaSetupAsk.matches("Hey Zeus, what happens when the lid closes?"))
        #expect(InsomniaSetupAsk.matches("insomnia settings"))
        #expect(!InsomniaSetupAsk.matches("how's the lid"))
        #expect(!InsomniaSetupAsk.matches("insomnia"))
        #expect(!InsomniaSetupAsk.matches("how's keep awake set"))
        #expect(!InsomniaSetupAsk.matches("where's the forecast from"))
    }
}
