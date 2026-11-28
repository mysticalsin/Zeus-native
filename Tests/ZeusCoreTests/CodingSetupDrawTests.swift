import Testing
@testable import ZeusCore

struct CodingSetupDrawTests {
    private func cards(_ plan: CodingSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theAgentAndTerminalFollowCode() {
        let usual = CodingSetupDraw.plan(agent: "Claude Code", terminal: "Automatic")
        #expect(cards(usual) == ["Code", "Agent: Claude Code", "Terminal: Automatic"])
        #expect(CodingSetupAsk.line(agent: "Claude Code", terminal: "Automatic") == "Coding uses Claude Code, and the terminal is Automatic.")
        #expect(usual.boltCaption(at: 0) == "Code")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Terminal: Automatic")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(cards(CodingSetupDraw.plan(agent: "Cursor Agent", terminal: "iTerm")) == ["Code", "Agent: Cursor Agent", "Terminal: iTerm"])
        #expect(CodingSetupAsk.line(agent: "Codex", terminal: "Ghostty") == "Coding uses Codex, and the terminal is Ghostty.")
        #expect(cards(CodingSetupDraw.plan(agent: "Safari", terminal: "Automatic")) == ["Code", "Can't"])
        #expect(CodingSetupAsk.line(agent: "Claude Code", terminal: "Kitty") == "I can't read how coding is set.")
    }

    @Test func aCodingTaskAndWhoAnswersStayOffThisAsk() {
        #expect(CodingSetupAsk.matches("how's coding set"))
        #expect(CodingSetupAsk.matches("Hey Zeus, which coding agent?"))
        #expect(CodingSetupAsk.matches("coding settings"))
        #expect(!CodingSetupAsk.matches("who answers"))
        #expect(!CodingSetupAsk.matches("what are my agents doing"))
        #expect(!CodingSetupAsk.matches("how's tiling set"))
    }
}
