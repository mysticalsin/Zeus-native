import Testing
@testable import ZeusCore

struct CommandSetupDrawTests {
    private func cards(_ plan: CommandSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallLeavesTheCommandOff() {
        let usual = CommandSetupDraw.plan(control: "Off", notice: "Clear")
        #expect(cards(usual) == ["Command", "Control: Off", "Notice: Clear"])
        #expect(CommandSetupAsk.line(control: "Off", notice: "Clear") == "Command-line control is off, and there is no reset notice.")
        #expect(usual.boltCaption(at: 0) == "Command")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Notice: Clear")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(CommandSetupAsk.line(control: "On", notice: "Waiting") == "Command-line control is on, and the reset notice is waiting.")
        #expect(cards(CommandSetupDraw.plan(control: "On", notice: "Clear")) == ["Command", "Control: On", "Notice: Clear"])
        #expect(cards(CommandSetupDraw.plan(control: "Maybe", notice: "Clear")) == ["Command", "Can't"])
        #expect(CommandSetupAsk.line(control: "On", notice: "secret") == "I can't read command-line control.")
    }

    @Test func drivingTheMacStaysOffThisAsk() {
        #expect(CommandSetupAsk.matches("how is command line control set"))
        #expect(CommandSetupAsk.matches("Hey Zeus, can the zeus command type?"))
        #expect(CommandSetupAsk.matches("command line settings"))
        #expect(!CommandSetupAsk.matches("when may zeus drive"))
        #expect(!CommandSetupAsk.matches("how's automation set"))
        #expect(!CommandSetupAsk.matches("which dictation microphone"))
        #expect(!CommandSetupAsk.matches("how is the voice tuned"))
    }
}
