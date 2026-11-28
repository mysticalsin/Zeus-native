import Testing
@testable import ZeusCore

struct TerminalOpenDrawTests {
    @Test func aBareTerminalAndANamedProject() throws {
        let bare = try #require(TerminalOpenDraw.from(summary: "Terminal"))
        let named = try #require(TerminalOpenDraw.from(summary: "Terminal: Zeus"))
        func cards(_ plan: TerminalOpenDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(bare) == ["Terminal"])
        #expect(bare.project == nil)
        #expect(bare.boltCaption(at: 0) == "Terminal")
        #expect(bare.boltCaption(at: 100) == "Terminal")
        #expect(bare.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(cards(named) == ["Terminal", "Zeus"])
        #expect(named.boltCaption(at: 0) == "Terminal")
        #expect(named.boltCaption(at: 100) == "Zeus")
        #expect(named.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(named.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankProjectAndOtherSummariesAreNotDrawn() {
        #expect(TerminalOpenDraw.from(summary: "Terminal: ") == nil)
        #expect(TerminalOpenDraw.from(summary: "Terminal:   ") == nil)
        #expect(TerminalOpenDraw.plan(project: " ") == nil)
        #expect(TerminalOpenDraw.from(summary: "Zeus in terminal") == nil)
        #expect(TerminalOpenDraw.from(summary: "Open Zeus in Terminal") == nil)
        #expect(TerminalOpenDraw.from(summary: "Research: tides") == nil)
        #expect(TerminalOpenDraw.from(summary: "Quit Terminal") == nil)
    }
}
