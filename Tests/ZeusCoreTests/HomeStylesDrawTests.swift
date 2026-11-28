import Testing
@testable import ZeusCore

struct HomeStylesDrawTests {
    private func cards(_ plan: HomeStylesDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theFourStylesFollowTheTitle() {
        let usual = HomeStylesDraw.plan(clock: "Analog", music: "Art", weather: "Summary", calendar: "Next event")
        #expect(cards(usual) == ["Styles", "Clock: Analog", "Music: Art", "Weather: Summary", "Calendar: Next event"])
        #expect(HomeStylesAsk.line(clock: "Analog", music: "Art", weather: "Summary", calendar: "Next event") == "The clock is Analog, music is Art, weather is Summary, and the calendar is Next event.")
        #expect(usual.boltCaption(at: 0) == "Styles")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Calendar: Next event")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(HomeStylesAsk.line(clock: "Blue halo", music: "Lyrics", weather: "Wind", calendar: "Agenda") == "The clock is Blue halo, music is Lyrics, weather is Wind, and the calendar is Agenda.")
        #expect(cards(HomeStylesDraw.plan(clock: "Analog", music: "Vinyl", weather: "Summary", calendar: "Next event")) == ["Styles", "Can't"])
        #expect(HomeStylesAsk.line(clock: "Square", music: "Art", weather: "Summary", calendar: "Month") == "I can't read the Home styles.")
    }

    @Test func whichCardsAreShowingStaysOffThisAsk() {
        #expect(HomeStylesAsk.matches("how's home styled"))
        #expect(HomeStylesAsk.matches("Hey Zeus, what's the clock style?"))
        #expect(HomeStylesAsk.matches("home style settings"))
        #expect(!HomeStylesAsk.matches("what's on home"))
        #expect(!HomeStylesAsk.matches("what's the card style"))
        #expect(!HomeStylesAsk.matches("what's the weather"))
        #expect(!HomeStylesAsk.matches("how's other apps set"))
    }
}
