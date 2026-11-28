import Testing
@testable import ZeusCore

struct BandSetupDrawTests {
    private func cards(_ plan: BandSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallShapesNothing() {
        let usual = BandSetupDraw.plan(shape: "Off", saved: "None", shaped: "None")
        #expect(cards(usual) == ["Bands", "Shape: Off", "Saved: None", "Shaped: None"])
        #expect(BandSetupAsk.line(shape: "Off", saved: "None", shaped: "None") == "Per-app sound is off, no apps are saved, and none are shaped.")
        #expect(usual.boltCaption(at: 0) == "Bands")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Shaped: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(BandSetupAsk.line(shape: "On", saved: "Chosen", shaped: "Some") == "Per-app sound is on, apps are saved, and some are shaped.")
        #expect(BandSetupAsk.line(shape: "Off", saved: "Unreadable", shaped: "None") == "Per-app sound is off, the saved apps could not be read, and none are shaped.")
        #expect(cards(BandSetupDraw.plan(shape: "On", saved: "None", shaped: "Some")) == ["Bands", "Can't"])
        #expect(BandSetupAsk.line(shape: "On", saved: "Mail", shaped: "None") == "I can't read per-app sound.")
    }

    @Test func theCueVolumeStaysOffThisAsk() {
        #expect(BandSetupAsk.matches("is per-app sound on"))
        #expect(BandSetupAsk.matches("Hey Zeus, how is the equaliser set?"))
        #expect(BandSetupAsk.matches("are any apps shaped"))
        #expect(!BandSetupAsk.matches("how is sound feedback set"))
        #expect(!BandSetupAsk.matches("what is the volume"))
        #expect(!BandSetupAsk.matches("does the halo match the wallpaper"))
        #expect(!BandSetupAsk.matches("how are arrival lights set"))
    }
}
