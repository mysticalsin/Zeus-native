import Testing
@testable import ZeusCore

struct BrowserStoppedDrawTests {
    @Test func aStoppedSeparateBrowserShowsStopped() throws {
        let plan = try #require(BrowserStoppedDraw.from(line: "The separate browser stopped."))
        func cards(_ plan: BrowserStoppedDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Browser", "Stopped"])
        #expect(plan.boltCaption(at: 0) == "Browser")
        #expect(plan.boltCaption(at: 100) == "Stopped")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anUnreadPageListAndAForgetAskAreNotThisStop() {
        #expect(BrowserStoppedDraw.from(line: "") == nil)
        #expect(BrowserStoppedDraw.from(line: "The separate browser stopped: it quit.") == nil)
        #expect(BrowserStoppedDraw.from(line: "the separate browser didn't start.") == nil)
        #expect(BrowserStoppedDraw.from(line: "the separate browser isn't set up yet. Open Settings, Features.") == nil)
        #expect(BrowserStoppedDraw.from(line: "The separate browser's page list couldn't be read.") == nil)
        #expect(BrowserStoppedDraw.from(line: "That matches 2 things: \"tea\", \"coffee\". Which one should I forget? Say it more exactly.") == nil)
    }
}
