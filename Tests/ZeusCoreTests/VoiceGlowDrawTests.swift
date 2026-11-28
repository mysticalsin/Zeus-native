import Testing
@testable import ZeusCore

struct VoiceGlowDrawTests {
    private func cards(_ plan: VoiceGlowDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theSwitchAndColorFollowGlow() {
        let usual = VoiceGlowDraw.plan(work: "On", color: "Colorful")
        #expect(cards(usual) == ["Glow", "Work: On", "Color: Colorful"])
        #expect(VoiceGlowAsk.line(work: "On", color: "Colorful") == "The voice glow is on, and the colors are Colorful.")
        #expect(usual.boltCaption(at: 0) == "Glow")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Color: Colorful")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(VoiceGlowAsk.line(work: "Off", color: "Ocean") == "The voice glow is off, and the colors are Ocean.")
        #expect(cards(VoiceGlowDraw.plan(work: "On", color: "Gold")) == ["Glow", "Work: On", "Color: Gold"])
        #expect(cards(VoiceGlowDraw.plan(work: "On", color: "Purple")) == ["Glow", "Can't"])
        #expect(VoiceGlowAsk.line(work: "Maybe", color: "Mono") == "I can't read the voice glow.")
    }

    @Test func theWritingModeAndTheChosenVoiceStayOffThisAsk() {
        #expect(VoiceGlowAsk.matches("how's the voice glow set"))
        #expect(VoiceGlowAsk.matches("Hey Zeus, which glow colors?"))
        #expect(VoiceGlowAsk.matches("voice glow settings"))
        #expect(!VoiceGlowAsk.matches("which dictation mode"))
        #expect(!VoiceGlowAsk.matches("which voice is this"))
        #expect(!VoiceGlowAsk.matches("which voice cues"))
        #expect(!VoiceGlowAsk.matches("how's dictation set"))
    }
}
