import Testing
@testable import ZeusCore

struct JevSetupDrawTests {
    private func cards(_ plan: JevSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func workKeyAndLimitFollowJev() {
        let usual = JevSetupDraw.plan(work: "Off", key: "None", limit: "None")
        #expect(cards(usual) == ["Jev", "Work: Off", "Key: None", "Limit: None"])
        #expect(JevSetupAsk.line(work: "Off", key: "None", limit: "None") == "Jev is off, no key is saved, and no monthly limit is set.")
        #expect(usual.boltCaption(at: 0) == "Jev")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Limit: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(JevSetupAsk.line(work: "On", key: "Saved", limit: "Set") == "Jev is on, a key is saved, and a monthly limit is set.")
        #expect(cards(JevSetupDraw.plan(work: "Off", key: "Saved", limit: "None")) == ["Jev", "Work: Off", "Key: Saved", "Limit: None"])
        #expect(cards(JevSetupDraw.plan(work: "Maybe", key: "None", limit: "None")) == ["Jev", "Can't"])
        #expect(JevSetupAsk.line(work: "Off", key: "Secret", limit: "None") == "I can't read how Jev is set.")
    }

    @Test func otherPermissionsStayOffThisAsk() {
        #expect(JevSetupAsk.matches("how's jev set"))
        #expect(JevSetupAsk.matches("Hey Zeus, is jev on?"))
        #expect(JevSetupAsk.matches("jev settings"))
        #expect(!JevSetupAsk.matches("which other permissions"))
        #expect(!JevSetupAsk.matches("how's research set"))
        #expect(!JevSetupAsk.matches("how long is dictation kept"))
        #expect(!JevSetupAsk.matches("is accessibility on"))
    }
}
