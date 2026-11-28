import Testing
@testable import ZeusCore

struct LeftOutDrawTests {
    private func cards(_ plan: LeftOutDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallLeavesEveryAppIn() {
        let usual = LeftOutDraw.plan(list: "None", count: "0")
        #expect(cards(usual) == ["Aside", "List: None", "Count: 0"])
        #expect(LeftOutAsk.line(list: "None", count: "0") == "Tiling leaves every app in.")
        #expect(usual.boltCaption(at: 0) == "Aside")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Count: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(LeftOutAsk.appCount(" com.example.app, com.other.app ") == 2)
        #expect(LeftOutAsk.appCount("") == 0)
        #expect(LeftOutAsk.line(list: "Some", count: "1") == "Tiling leaves 1 app out.")
        #expect(LeftOutAsk.line(list: "Some", count: "3") == "Tiling leaves 3 apps out.")
        #expect(cards(LeftOutDraw.plan(list: "Some", count: "0")) == ["Aside", "Can't"])
        #expect(LeftOutAsk.line(list: "None", count: "com.example.app") == "I can't read which apps tiling leaves out.")
    }

    @Test func theTilingSwitchStaysOffThisAsk() {
        #expect(LeftOutAsk.matches("which apps does tiling leave out"))
        #expect(LeftOutAsk.matches("Hey Zeus, are any apps left out of tiling?"))
        #expect(LeftOutAsk.matches("tiling leave out settings"))
        #expect(!LeftOutAsk.matches("how is tiling set"))
        #expect(!LeftOutAsk.matches("how are the tiling gaps"))
        #expect(!LeftOutAsk.matches("what always asks"))
        #expect(!LeftOutAsk.matches("how is the admin rule set"))
    }
}
