import Testing
@testable import ZeusCore

struct CompanionDrawTests {
    private func cards(_ plan: CompanionDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallIsClassicWithZeusInTheNotch() {
        let usual = CompanionDraw.plan(look: "Classic", face: "Zeus")
        #expect(cards(usual) == ["Companion", "Look: Classic", "Face: Zeus"])
        #expect(CompanionAsk.line(look: "Classic", face: "Zeus") == "The companion is Classic, and the agent face is Zeus.")
        #expect(usual.boltCaption(at: 0) == "Companion")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Face: Zeus")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(CompanionAsk.line(look: "Orb (Jarvis)", face: "Glyphs") == "The companion is Orb, and the agent face is Glyphs.")
        #expect(cards(CompanionDraw.plan(look: "Ultron", face: "Zeus")) == ["Companion", "Can't"])
        #expect(CompanionAsk.line(look: "Classic", face: "Bolt") == "I can't read the companion.")
    }

    @Test func thePointerBuddyStaysOffThisAsk() {
        #expect(CompanionAsk.matches("how is the companion set"))
        #expect(CompanionAsk.matches("Hey Zeus, which agent face?"))
        #expect(CompanionAsk.matches("is mini zeus in the notch"))
        #expect(!CompanionAsk.matches("when does zeus appear"))
        #expect(!CompanionAsk.matches("what is the personality"))
        #expect(!CompanionAsk.matches("which pointing provider"))
        #expect(!CompanionAsk.matches("how big is the drawn notch"))
    }
}
