import Testing
@testable import ZeusCore

struct VisualReadyDrawTests {
    private func cards(_ plan: VisualReadyDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallLeavesExplanationsOff() {
        let usual = VisualReadyDraw.plan(work: "Off", endpoint: "Missing")
        #expect(cards(usual) == ["Visual", "Switch: Off", "Endpoint: Missing"])
        #expect(VisualReadyAsk.line(work: "Off", endpoint: "Missing") == "Visual explanations are off, and no endpoint is ready.")
        #expect(usual.boltCaption(at: 0) == "Visual")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Endpoint: Missing")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(VisualReadyAsk.line(work: "On", endpoint: "Ready") == "Visual explanations are on, and an endpoint is ready.")
        #expect(VisualReadyAsk.line(work: "On", endpoint: "Missing") == "Visual explanations are on, and no endpoint is ready.")
        #expect(cards(VisualReadyDraw.plan(work: "Yes", endpoint: "Missing")) == ["Visual", "Can't"])
        #expect(VisualReadyAsk.line(work: "Off", endpoint: "Set") == "I can't read whether visual explanations are on.")
    }

    @Test func theShortcutStaysOffThisAsk() {
        #expect(VisualReadyAsk.matches("are visual explanations on"))
        #expect(VisualReadyAsk.matches("Hey Zeus, is visual explanation enabled?"))
        #expect(VisualReadyAsk.matches("can visual explanations run"))
        #expect(!VisualReadyAsk.matches("how is the explanation set"))
        #expect(!VisualReadyAsk.matches("how is visual explanation set"))
        #expect(!VisualReadyAsk.matches("how is any llm set"))
        #expect(!VisualReadyAsk.matches("how many macs are paired"))
    }
}
