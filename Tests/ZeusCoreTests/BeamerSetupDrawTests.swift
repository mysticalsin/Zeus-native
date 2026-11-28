import Testing
@testable import ZeusCore

struct BeamerSetupDrawTests {
    private func cards(_ plan: BeamerSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func startLightAndTabFollowLink() {
        let usual = BeamerSetupDraw.plan(start: "Off", light: "On", tab: "Off")
        #expect(cards(usual) == ["Link", "Start: Off", "Light: On", "Tab: Off"])
        #expect(BeamerSetupAsk.line(start: "Off", light: "On", tab: "Off") == "Beamer start is off, the crossing light is on, and the Continuity tab is off.")
        #expect(usual.boltCaption(at: 0) == "Link")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Tab: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(BeamerSetupAsk.line(start: "On", light: "Off", tab: "On") == "Beamer start is on, the crossing light is off, and the Continuity tab is on.")
        #expect(cards(BeamerSetupDraw.plan(start: "Maybe", light: "On", tab: "Off")) == ["Link", "Can't"])
        #expect(BeamerSetupAsk.line(start: "On", light: "Bright", tab: "Off") == "I can't read how Beamer is set.")
    }

    @Test func whereTheKeyboardIsStaysOffThisAsk() {
        #expect(BeamerSetupAsk.matches("how's beamer set"))
        #expect(BeamerSetupAsk.matches("Hey Zeus, is the continuity tab on?"))
        #expect(BeamerSetupAsk.matches("beamer settings"))
        #expect(!BeamerSetupAsk.matches("how's beamer"))
        #expect(!BeamerSetupAsk.matches("where is my keyboard"))
        #expect(!BeamerSetupAsk.matches("how's receiving set"))
        #expect(!BeamerSetupAsk.matches("start beamer"))
    }
}
