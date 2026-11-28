import Testing
@testable import ZeusCore

struct HudExtrasDrawTests {
    private func cards(_ plan: HudExtrasDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func lightsThatAreOnFollowGlow() {
        let usual = HudExtrasDraw.plan(words: ["Mute", "HUD", "Edge", "Event"])
        #expect(cards(usual) == ["Pulse", "Mute", "HUD", "Edge", "Event"])
        #expect(HudExtrasAsk.line(words: ["Mute", "HUD", "Edge", "Event"]) == "Mute, HUD, Edge, and Event are on.")
        #expect(usual.boltCaption(at: 0) == "Pulse")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Event")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        let all = HudExtrasDraw.plan(words: ["Mute", "HUD", "Edge", "Peeks", "Event"])
        #expect(cards(all) == ["Pulse", "Mute", "HUD", "Edge", "Peeks"])
        #expect(HudExtrasAsk.line(words: ["Mute", "HUD", "Edge", "Peeks", "Event"]) == "5 other notch lights are on, starting Mute, HUD, Edge, and Peeks.")
        #expect(cards(HudExtrasDraw.plan(words: [])) == ["Pulse", "None"])
        #expect(HudExtrasAsk.line(words: []) == "The other notch lights are off.")
        #expect(cards(HudExtrasDraw.plan(words: ["Event", "Mute"])) == ["Pulse", "Can't"])
        #expect(HudExtrasAsk.line(words: ["Volume"]) == "I can't read the other notch lights.")
    }

    @Test func theLevelLightsStayOffThisAsk() {
        #expect(HudExtrasAsk.matches("which other notch lights"))
        #expect(HudExtrasAsk.matches("Hey Zeus, are shortcut peeks on?"))
        #expect(HudExtrasAsk.matches("other notch light settings"))
        #expect(!HudExtrasAsk.matches("which notch lights"))
        #expect(!HudExtrasAsk.matches("which hud lights"))
        #expect(!HudExtrasAsk.matches("which everyday lights"))
        #expect(!HudExtrasAsk.matches("which extra sounds"))
    }
}
