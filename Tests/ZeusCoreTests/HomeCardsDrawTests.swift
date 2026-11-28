import Testing
@testable import ZeusCore

struct HomeCardsDrawTests {
    private func cards(_ plan: HomeCardsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func fourCardsFollowHome() {
        let home = HomeCardsDraw.plan(words: ["Music", "Focus", "Weather", "Calendar"])
        #expect(cards(home) == ["Home", "Music", "Focus", "Weather", "Calendar"])
        #expect(HomeCardsAsk.line(words: ["Music", "Focus", "Weather", "Calendar"]) == "Home shows Music, Focus, Weather, and Calendar.")
        #expect(home.boltCaption(at: 0) == "Home")
        #expect(home.boltCaption(at: ExplainBeatSchedule.gap * 4) == "Calendar")
        #expect(home.guideBolt(at: ExplainBeatSchedule.gap * 4) == TalkDraw.Point(x: 920, y: 390))
        #expect(HomeCardsAsk.line(words: ["World clock", "Note", "Battery", "Agents"]) == "Home shows World clock, Note, Battery, and Agents.")
        #expect(cards(HomeCardsDraw.plan(words: ["Music"])) == ["Home", "Can't"])
        #expect(HomeCardsAsk.line(words: []) == "I can't read the Home cards.")
    }

    @Test func theAgendaAndTheShelfStayOffThisAsk() {
        #expect(HomeCardsAsk.matches("what's on home"))
        #expect(HomeCardsAsk.matches("Hey Zeus, which home cards?"))
        #expect(HomeCardsAsk.matches("home cards"))
        #expect(!HomeCardsAsk.matches("what's on my agenda"))
        #expect(!HomeCardsAsk.matches("what's on my shelf"))
        #expect(!HomeCardsAsk.matches("what do I have today"))
        #expect(!HomeCardsAsk.matches("what's the halo"))
    }
}
