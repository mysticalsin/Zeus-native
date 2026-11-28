import Testing
@testable import ZeusCore

struct HomeLaterDrawTests {
    private func cards(_ plan: HomeLaterDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallUsesTheDefaultCities() {
        let usual = HomeLaterDraw.plan(cities: "Default", title: "None", day: "None")
        #expect(cards(usual) == ["Later", "Cities: Default", "Title: None", "Day: None"])
        #expect(HomeLaterAsk.line(cities: "Default", title: "None", day: "None") == "The world clock uses the default cities, the countdown has no title, and it has no day.")
        #expect(usual.boltCaption(at: 0) == "Later")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Day: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(HomeLaterAsk.line(cities: "Custom", title: "Set", day: "2026-12-25") == "The world clock uses your own cities, the countdown has a title, and the day is 2026-12-25.")
        #expect(cards(HomeLaterDraw.plan(cities: "None", title: "None", day: "None")) == ["Later", "Cities: None", "Title: None", "Day: None"])
        #expect(cards(HomeLaterDraw.plan(cities: "Default", title: "None", day: "soon")) == ["Later", "Can't"])
        #expect(HomeLaterAsk.line(cities: "Default", title: "Launch day", day: "None") == "I can't read the world clock or the countdown.")
    }

    @Test func theDaysLeftStayOffThisAsk() {
        #expect(HomeLaterAsk.matches("how is the world clock set"))
        #expect(HomeLaterAsk.matches("Hey Zeus, when is the countdown?"))
        #expect(HomeLaterAsk.matches("which world clock cities"))
        #expect(!HomeLaterAsk.matches("what is the countdown"))
        #expect(!HomeLaterAsk.matches("how many days left"))
        #expect(!HomeLaterAsk.matches("how's home styled"))
        #expect(!HomeLaterAsk.matches("how is the hotspot set"))
    }
}
