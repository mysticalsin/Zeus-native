import Testing
@testable import ZeusCore

struct ShareSetupDrawTests {
    private func cards(_ plan: ShareSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallSharesProjectDetailsOnly() {
        let usual = ShareSetupDraw.plan(details: "On", lyrics: "Off", chrome: "Off")
        #expect(cards(usual) == ["Share", "Details: On", "Lyrics: Off", "Chrome: Off"])
        #expect(ShareSetupAsk.line(details: "On", lyrics: "Off", chrome: "Off") == "Project details are on, synced lyrics are off, and Chrome media is off.")
        #expect(usual.boltCaption(at: 0) == "Share")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Chrome: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(ShareSetupAsk.line(details: "Off", lyrics: "On", chrome: "On") == "Project details are off, synced lyrics are on, and Chrome media is on.")
        #expect(cards(ShareSetupDraw.plan(details: "Off", lyrics: "Off", chrome: "Off")) == ["Share", "Details: Off", "Lyrics: Off", "Chrome: Off"])
        #expect(cards(ShareSetupDraw.plan(details: "Maybe", lyrics: "Off", chrome: "Off")) == ["Share", "Can't"])
        #expect(ShareSetupAsk.line(details: "On", lyrics: "Soon", chrome: "Off") == "I can't read what Zeus shares.")
    }

    @Test func theTrackStaysOffThisAsk() {
        #expect(ShareSetupAsk.matches("how is privacy set"))
        #expect(ShareSetupAsk.matches("Hey Zeus, are synced lyrics on?"))
        #expect(ShareSetupAsk.matches("privacy settings"))
        #expect(!ShareSetupAsk.matches("which music lights"))
        #expect(!ShareSetupAsk.matches("how's the music source"))
        #expect(!ShareSetupAsk.matches("which agents are offered"))
        #expect(!ShareSetupAsk.matches("how's day to day"))
    }
}
