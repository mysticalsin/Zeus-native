import Testing
@testable import ZeusCore

struct HomeBackdropDrawTests {
    private func cards(_ plan: HomeBackdropDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func lookAndMotionFollowBehind() {
        let usual = HomeBackdropDraw.plan(look: "None", motion: "Still")
        #expect(cards(usual) == ["Behind", "Look: None", "Motion: Still"])
        #expect(HomeBackdropAsk.line(look: "None", motion: "Still") == "The Home backdrop is None, and it is still.")
        #expect(usual.boltCaption(at: 0) == "Behind")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Motion: Still")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(HomeBackdropAsk.line(look: "Aurora", motion: "Moves") == "The Home backdrop is Aurora, and it moves.")
        #expect(HomeBackdropAsk.line(look: "Terrazzo", motion: "Still") == "The Home backdrop is Terrazzo, and it is still.")
        #expect(cards(HomeBackdropDraw.plan(look: "Low-poly", motion: "Still")) == ["Behind", "Look: Low-poly", "Motion: Still"])
        #expect(cards(HomeBackdropDraw.plan(look: "Sparkle", motion: "Moves")) == ["Behind", "Can't"])
        #expect(HomeBackdropAsk.line(look: "None", motion: "Spins") == "I can't read the Home backdrop.")
    }

    @Test func theHomeCardsStayOffThisAsk() {
        #expect(HomeBackdropAsk.matches("what's the home backdrop"))
        #expect(HomeBackdropAsk.matches("Hey Zeus, does the home backdrop move?"))
        #expect(HomeBackdropAsk.matches("home backdrop settings"))
        #expect(!HomeBackdropAsk.matches("how's home styled"))
        #expect(!HomeBackdropAsk.matches("which home cards"))
        #expect(!HomeBackdropAsk.matches("what is on home"))
        #expect(!HomeBackdropAsk.matches("how's the notchless shape"))
    }
}
