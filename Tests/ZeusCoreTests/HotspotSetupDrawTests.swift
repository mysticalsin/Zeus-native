import Testing
@testable import ZeusCore

struct HotspotSetupDrawTests {
    private func cards(_ plan: HotspotSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallHasNoHotspot() {
        let usual = HotspotSetupDraw.plan(name: "None", password: "None")
        #expect(cards(usual) == ["Hotspot", "Name: None", "Password: None"])
        #expect(HotspotSetupAsk.line(name: "None", password: "None") == "The hotspot name is not set, and no password is saved.")
        #expect(usual.boltCaption(at: 0) == "Hotspot")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Password: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(HotspotSetupAsk.line(name: "Chosen", password: "Saved") == "A hotspot name is set, and a password is saved.")
        #expect(cards(HotspotSetupDraw.plan(name: "Chosen", password: "None")) == ["Hotspot", "Name: Chosen", "Password: None"])
        #expect(cards(HotspotSetupDraw.plan(name: "iPhone", password: "None")) == ["Hotspot", "Can't"])
        #expect(HotspotSetupAsk.line(name: "None", password: "secret") == "I can't read the hotspot.")
    }

    @Test func insomniaStaysOffThisAsk() {
        #expect(HotspotSetupAsk.matches("how is the hotspot set"))
        #expect(HotspotSetupAsk.matches("Hey Zeus, is a hotspot password saved?"))
        #expect(HotspotSetupAsk.matches("hotspot settings"))
        #expect(!HotspotSetupAsk.matches("how is insomnia set"))
        #expect(!HotspotSetupAsk.matches("how is the nudge set"))
        #expect(!HotspotSetupAsk.matches("how are the tiling gaps"))
        #expect(!HotspotSetupAsk.matches("how is tiling set"))
    }
}
