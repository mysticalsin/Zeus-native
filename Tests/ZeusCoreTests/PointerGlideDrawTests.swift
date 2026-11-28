import Testing
@testable import ZeusCore

struct PointerGlideDrawTests {
    private func cards(_ plan: PointerGlideDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshPointerStaysOffInBothPlaces() {
        let usual = PointerGlideDraw.plan(shown: "Off", engine: "Off")
        #expect(cards(usual) == ["Glide", "Switch: Off", "Engine: Off"])
        #expect(PointerGlideAsk.line(shown: "Off", engine: "Off") == "The pointer switch is off, and the pointer engine is off.")
        #expect(usual.boltCaption(at: 0) == "Glide")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Engine: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(PointerGlideAsk.line(shown: "On", engine: "Off") == "The pointer switch is on, and the pointer engine is off.")
        #expect(PointerGlideAsk.line(shown: "On", engine: "On") == "The pointer switch is on, and the pointer engine is on.")
        #expect(cards(PointerGlideDraw.plan(shown: "Yes", engine: "Off")) == ["Glide", "Can't"])
        #expect(PointerGlideAsk.line(shown: "Off", engine: "Maybe") == "I can't read the system pointer.")
    }

    @Test func drivePermissionStaysOffThisAsk() {
        #expect(PointerGlideAsk.matches("does zeus move the system pointer"))
        #expect(PointerGlideAsk.matches("Hey Zeus, is the pointer engine on?"))
        #expect(PointerGlideAsk.matches("how is the system pointer set"))
        #expect(!PointerGlideAsk.matches("when may zeus drive"))
        #expect(!PointerGlideAsk.matches("how is the pointing trail set"))
        #expect(!PointerGlideAsk.matches("are quick cues on"))
        #expect(!PointerGlideAsk.matches("does zeus sit next to the cursor"))
    }
}
