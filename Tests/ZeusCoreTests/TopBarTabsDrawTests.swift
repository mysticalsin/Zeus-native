import Testing
@testable import ZeusCore

struct TopBarTabsDrawTests {
    private func cards(_ plan: TopBarTabsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theFirstFourNamesFollowTabs() {
        let four = ["Home", "Tiling", "Agents", "Chat"]
        let row = TopBarTabsDraw.plan(words: four)
        #expect(cards(row) == ["Tabs", "Home", "Tiling", "Agents", "Chat"])
        #expect(TopBarTabsAsk.line(words: four) == "The bar shows Home, Tiling, Agents, and Chat.")
        #expect(row.boltCaption(at: 0) == "Tabs")
        #expect(row.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Chat")
        #expect(row.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        let six = four + ["Alerts", "Clipboard"]
        #expect(cards(TopBarTabsDraw.plan(words: six)) == ["Tabs", "Home", "Tiling", "Agents", "Chat"])
        #expect(TopBarTabsAsk.line(words: six) == "The bar shows 6 tabs, starting Home, Tiling, Agents, and Chat.")
        #expect(TopBarTabsAsk.line(words: ["Home"]) == "The bar shows Home.")
        #expect(cards(TopBarTabsDraw.plan(words: ["Chat"])) == ["Tabs", "Can't"])
        #expect(TopBarTabsAsk.line(words: []) == "I can't read the top bar tabs.")
    }

    @Test func homeCardsAndTheNotchLightsStayOffThisAsk() {
        #expect(TopBarTabsAsk.matches("which tabs are on"))
        #expect(TopBarTabsAsk.matches("Hey Zeus, how's the top bar?"))
        #expect(TopBarTabsAsk.matches("top bar tabs"))
        #expect(!TopBarTabsAsk.matches("what's on home"))
        #expect(!TopBarTabsAsk.matches("which notch lights"))
        #expect(!TopBarTabsAsk.matches("where's the notch"))
        #expect(!TopBarTabsAsk.matches("what's the halo"))
    }
}
