import Testing
@testable import ZeusCore

struct AgentFinishDrawTests {
    private func cards(_ plan: AgentFinishDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallShowsACardAndStaysQuiet() {
        let usual = AgentFinishDraw.plan(card: "On", sound: "On", quiet: "On", voice: "Off")
        #expect(cards(usual) == ["Finish", "Card: On", "Sound: On", "Quiet: On", "Voice: Off"])
        #expect(AgentFinishAsk.line(card: "On", sound: "On", quiet: "On", voice: "Off") == "Finish cards are on, the finish sound is on, full-screen quiet is on, and voice stop is off.")
        #expect(usual.boltCaption(at: 0) == "Finish")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Voice: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(AgentFinishAsk.line(card: "Off", sound: "Off", quiet: "Off", voice: "On") == "Finish cards are off, the finish sound is off, full-screen quiet is off, and voice stop is on.")
        #expect(cards(AgentFinishDraw.plan(card: "Yes", sound: "On", quiet: "On", voice: "Off")) == ["Finish", "Can't"])
        #expect(AgentFinishAsk.line(card: "On", sound: "Maybe", quiet: "On", voice: "Off") == "I can't read how finished agents are shown.")
    }

    @Test func aRunningAgentStaysOffThisAsk() {
        #expect(AgentFinishAsk.matches("how are finished agents shown"))
        #expect(AgentFinishAsk.matches("Hey Zeus, can I stop agents by voice?"))
        #expect(AgentFinishAsk.matches("are agents quiet in full screen"))
        #expect(!AgentFinishAsk.matches("how is the second brain set"))
        #expect(!AgentFinishAsk.matches("how are to-dos set"))
        #expect(!AgentFinishAsk.matches("which agents are offered"))
        #expect(!AgentFinishAsk.matches("what is the second talk key"))
    }
}
