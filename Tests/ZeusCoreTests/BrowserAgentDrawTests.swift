import Testing
@testable import ZeusCore

struct BrowserAgentDrawTests {
    private func cards(_ plan: BrowserAgentDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func workStepsAndBrowserFollowTheTitle() {
        let usual = BrowserAgentDraw.plan(work: "On", steps: "25", browser: "Your Chrome")
        #expect(cards(usual) == ["Browser", "Work: On", "Steps: 25", "Browser: Your Chrome"])
        #expect(BrowserAgentAsk.line(work: "On", steps: "25", browser: "Your Chrome") == "The browser agent is on, stops after 25 steps, and uses Your Chrome.")
        #expect(usual.boltCaption(at: 0) == "Browser")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Browser: Your Chrome")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        let separate = BrowserAgentDraw.plan(work: "Off", steps: "60", browser: "Separate browser (browser-use)")
        #expect(cards(separate) == ["Browser", "Work: Off", "Steps: 60", "Browser: Separate browser (browser-use)"])
        #expect(BrowserAgentAsk.line(work: "Off", steps: "60", browser: "Separate browser (browser-use)") == "The browser agent is off, stops after 60 steps, and uses Separate browser (browser-use).")
        #expect(cards(BrowserAgentDraw.plan(work: "On", steps: "7", browser: "Your Chrome")) == ["Browser", "Can't"])
        #expect(BrowserAgentAsk.line(work: "Maybe", steps: "25", browser: "Safari") == "I can't read the browser agent.")
    }

    @Test func aWebTaskAndThePrompterStayOffThisAsk() {
        #expect(BrowserAgentAsk.matches("how's the browser agent set"))
        #expect(BrowserAgentAsk.matches("Hey Zeus, which browser does the agent use?"))
        #expect(BrowserAgentAsk.matches("browser agent settings"))
        #expect(!BrowserAgentAsk.matches("how's the prompter set"))
        #expect(!BrowserAgentAsk.matches("can you drive"))
        #expect(!BrowserAgentAsk.matches("start live translation"))
    }
}
