import Testing
@testable import ZeusCore

struct OpenPageDrawTests {
    private func cards(_ plan: OpenPageDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theOpenPageAndTheMoreMenu() {
        let usual = OpenPageDraw.plan(page: "Home", menu: "Off", edit: "Off")
        #expect(cards(usual) == ["Open", "Page: Home", "Menu: Off", "Edit: Off"])
        #expect(OpenPageAsk.line(page: "Home", menu: "Off", edit: "Off") == "The open page is Home, the more menu is closed, and tab editing is off.")
        #expect(usual.boltCaption(at: 0) == "Open")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Edit: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(OpenPageAsk.line(page: "Calendar", menu: "On", edit: "Off") == "The open page is Calendar, the more menu is open, and tab editing is off.")
        #expect(OpenPageAsk.line(page: "To-do", menu: "Off", edit: "On") == "The open page is To-do, the more menu is closed, and tab editing is on.")
        #expect(cards(OpenPageDraw.plan(page: "Notes", menu: "Off", edit: "Off")) == ["Open", "Can't"])
        #expect(OpenPageAsk.line(page: "Home", menu: "Maybe", edit: "Off") == "I can't read the open notch.")
    }

    @Test func theTabSwitchesStayOffThisAsk() {
        #expect(OpenPageAsk.matches("which tab is open"))
        #expect(OpenPageAsk.matches("Hey Zeus, is the more menu open?"))
        #expect(OpenPageAsk.matches("is tab editing on"))
        #expect(!OpenPageAsk.matches("which tabs are on"))
        #expect(!OpenPageAsk.matches("which tabs are showing"))
        #expect(!OpenPageAsk.matches("how many shelf files are verified"))
        #expect(!OpenPageAsk.matches("is the calendar on today"))
    }
}
