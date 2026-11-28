import Testing
@testable import ZeusCore

struct ResearchSetupDrawTests {
    private func cards(_ plan: ResearchSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func depthAndSaveFollowDepth() {
        let usual = ResearchSetupDraw.plan(depth: "Quick", save: "Default")
        #expect(cards(usual) == ["Depth", "Depth: Quick", "Save: Default"])
        #expect(ResearchSetupAsk.line(depth: "Quick", save: "Default") == "Research is Quick, and reports save in the default folder.")
        #expect(usual.boltCaption(at: 0) == "Depth")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Save: Default")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ResearchSetupAsk.line(depth: "Deep", save: "Chosen") == "Research is Deep, and reports save in a folder you chose.")
        #expect(cards(ResearchSetupDraw.plan(depth: "Deep", save: "Default")) == ["Depth", "Depth: Deep", "Save: Default"])
        #expect(cards(ResearchSetupDraw.plan(depth: "Long", save: "Default")) == ["Depth", "Can't"])
        #expect(ResearchSetupAsk.line(depth: "Quick", save: "Path") == "I can't read the research settings.")
    }

    @Test func startingResearchStaysOffThisAsk() {
        #expect(ResearchSetupAsk.matches("how's research set"))
        #expect(ResearchSetupAsk.matches("Hey Zeus, where's research saved?"))
        #expect(ResearchSetupAsk.matches("research settings"))
        #expect(!ResearchSetupAsk.matches("research quantum batteries"))
        #expect(!ResearchSetupAsk.matches("deep research quantum batteries"))
        #expect(!ResearchSetupAsk.matches("how's face presence set"))
        #expect(!ResearchSetupAsk.matches("how's lock and wake set"))
    }
}
