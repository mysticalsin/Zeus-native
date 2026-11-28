import Testing
@testable import ZeusCore

struct TalkSightDrawTests {
    private func cards(_ plan: TalkSightDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallSeesTheScreenAndDoesNotDraw() {
        let usual = TalkSightDraw.plan(see: "On", draw: "Off")
        #expect(cards(usual) == ["Sight", "See: On", "Draw: Off"])
        #expect(TalkSightAsk.line(see: "On", draw: "Off") == "Talk can see the screen, and it does not draw while answering.")
        #expect(usual.boltCaption(at: 0) == "Sight")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Draw: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(TalkSightAsk.line(see: "Off", draw: "On") == "Talk does not see the screen, and it draws while answering.")
        #expect(TalkSightAsk.line(see: "On", draw: "On") == "Talk can see the screen, and it draws while answering.")
        #expect(cards(TalkSightDraw.plan(see: "Yes", draw: "Off")) == ["Sight", "Can't"])
        #expect(TalkSightAsk.line(see: "Maybe", draw: "Off") == "I can't read whether talk can see the screen.")
    }

    @Test func screenRecordingStaysOffThisAsk() {
        #expect(TalkSightAsk.matches("how is talk sight set"))
        #expect(TalkSightAsk.matches("Hey Zeus, does talk see the screen?"))
        #expect(TalkSightAsk.matches("does zeus draw while it answers"))
        #expect(!TalkSightAsk.matches("can you see the screen"))
        #expect(!TalkSightAsk.matches("can you see my screen"))
        #expect(!TalkSightAsk.matches("how is the pointing trail set"))
        #expect(!TalkSightAsk.matches("which talk microphone"))
    }
}
