import Testing
@testable import ZeusCore

struct VoiceStyleDrawTests {
    private func cards(_ plan: VoiceStyleDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func speechToneOrbAndEffectFollowTone() {
        let usual = VoiceStyleDraw.plan(speak: "On", tone: "Ultron", orb: "Mascot", effect: "Off")
        #expect(cards(usual) == ["Tone", "Speak: On", "Tone: Ultron", "Orb: Mascot", "Effect: Off"])
        #expect(VoiceStyleAsk.line(speak: "On", tone: "Ultron", orb: "Mascot", effect: "Off") == "Replies are on, personality is Ultron, the orb is Mascot, and the effect is off.")
        #expect(usual.boltCaption(at: 0) == "Tone")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Effect: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(VoiceStyleAsk.line(speak: "Off", tone: "Plain", orb: "Mono ring", effect: "On") == "Replies are off, personality is Plain, the orb is Mono ring, and the effect is on.")
        #expect(cards(VoiceStyleDraw.plan(speak: "On", tone: "Ultron", orb: "Ring", effect: "Off")) == ["Tone", "Speak: On", "Tone: Ultron", "Orb: Ring", "Effect: Off"])
        #expect(cards(VoiceStyleDraw.plan(speak: "On", tone: "Funny", orb: "Mascot", effect: "Off")) == ["Tone", "Can't"])
        #expect(VoiceStyleAsk.line(speak: "Maybe", tone: "Ultron", orb: "Mascot", effect: "Off") == "I can't read how the voice is styled.")
    }

    @Test func theChosenVoiceStaysOffThisAsk() {
        #expect(VoiceStyleAsk.matches("how's the voice styled"))
        #expect(VoiceStyleAsk.matches("Hey Zeus, which voice orb?"))
        #expect(VoiceStyleAsk.matches("voice style settings"))
        #expect(!VoiceStyleAsk.matches("which voice"))
        #expect(!VoiceStyleAsk.matches("which voice is this"))
        #expect(!VoiceStyleAsk.matches("how's the voice glow set"))
        #expect(!VoiceStyleAsk.matches("how's the running card set"))
    }
}
