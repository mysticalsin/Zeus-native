import Testing
@testable import ZeusCore

struct BrowserSetupDrawTests {
    @Test func aSeparateBrowserNotSetUpShowsSetup() throws {
        let plan = try #require(BrowserSetupDraw.from(line: "the separate browser isn't set up yet. Open Settings, Features."))
        func cards(_ plan: BrowserSetupDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Browser", "Setup"])
        #expect(plan.boltCaption(at: 0) == "Browser")
        #expect(plan.boltCaption(at: 100) == "Setup")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anAgentOffAndAnUnreadMemoryAreNotSetup() {
        #expect(BrowserSetupDraw.from(line: "") == nil)
        #expect(BrowserSetupDraw.from(line: "the separate browser isn't set up yet. Open Settings, Features, Browser agent and press Set up.") == nil)
        #expect(BrowserSetupDraw.from(line: "the browser agent is off. Turn it on in Settings.") == nil)
        #expect(BrowserSetupDraw.from(line: "I can't read my memory file, so I left it alone.") == nil)
        #expect(BrowserSetupDraw.from(line: "Zeus isn't ready yet.") == nil)
    }
}
