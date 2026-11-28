import Testing
@testable import ZeusCore

struct WavesSetupDrawTests {
    private func cards(_ plan: WavesSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func styleAndHearFollowSpectrum() {
        let usual = WavesSetupDraw.plan(style: "Bars", hear: "Not asked yet")
        #expect(cards(usual) == ["Spectrum", "Style: Bars", "Hear: Not asked yet"])
        #expect(WavesSetupAsk.line(style: "Bars", hear: "Not asked yet") == "The waves are Bars, and system audio has not been asked yet.")
        #expect(usual.boltCaption(at: 0) == "Spectrum")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Hear: Not asked yet")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(WavesSetupAsk.line(style: "Mirror", hear: "Allowed") == "The waves are Mirror, and system audio is allowed.")
        #expect(WavesSetupAsk.line(style: "Wave", hear: "Denied") == "The waves are Wave, and system audio is denied.")
        #expect(cards(WavesSetupDraw.plan(style: "Wave", hear: "Allowed")) == ["Spectrum", "Style: Wave", "Hear: Allowed"])
        #expect(cards(WavesSetupDraw.plan(style: "Dots", hear: "Allowed")) == ["Spectrum", "Can't"])
        #expect(WavesSetupAsk.line(style: "Bars", hear: "On") == "I can't read the waves.")
    }

    @Test func theMusicLightsStayOffThisAsk() {
        #expect(WavesSetupAsk.matches("how's the waves set"))
        #expect(WavesSetupAsk.matches("Hey Zeus, is system audio allowed?"))
        #expect(WavesSetupAsk.matches("waves settings"))
        #expect(!WavesSetupAsk.matches("which music lights"))
        #expect(!WavesSetupAsk.matches("which other notch lights"))
        #expect(!WavesSetupAsk.matches("which tabs are on"))
        #expect(!WavesSetupAsk.matches("is screen recording on"))
    }
}
