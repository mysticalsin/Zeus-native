import Testing
@testable import ZeusCore

struct LivesDrawTests {
    private func cards(_ plan: LivesDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallKeepsTheIconAndGregorianDates() {
        let usual = LivesDraw.plan(menu: "On", dates: "Gregorian")
        #expect(cards(usual) == ["Lives", "Menu: On", "Dates: Gregorian"])
        #expect(LivesAsk.line(menu: "On", dates: "Gregorian") == "The menu bar icon is on, and dates stay Gregorian.")
        #expect(usual.boltCaption(at: 0) == "Lives")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Dates: Gregorian")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(LivesAsk.line(menu: "Off", dates: "Mac") == "The menu bar icon is off, and dates follow this Mac's calendar.")
        #expect(cards(LivesDraw.plan(menu: "Yes", dates: "Gregorian")) == ["Lives", "Can't"])
        #expect(LivesAsk.line(menu: "On", dates: "Persian") == "I can't read where Zeus lives.")
    }

    @Test func todaysDateStaysOffThisAsk() {
        #expect(LivesAsk.matches("is the menu bar icon on"))
        #expect(LivesAsk.matches("Hey Zeus, which calendar do dates use?"))
        #expect(LivesAsk.matches("where zeus lives"))
        #expect(!LivesAsk.matches("what is the date"))
        #expect(!LivesAsk.matches("is mini zeus in the notch"))
        #expect(!LivesAsk.matches("is show me on"))
        #expect(!LivesAsk.matches("are visual explanations on"))
    }
}
