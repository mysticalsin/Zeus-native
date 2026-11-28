import Testing
@testable import ZeusCore

struct EverydayLightsDrawTests {
    private func cards(_ plan: EverydayLightsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theLightsThatAreOnFollowMoments() {
        let all = EverydayLightsAsk.order
        let usual = EverydayLightsDraw.plan(words: all)
        #expect(cards(usual) == ["Moments", "Battery", "Rain", "Timer", "Mic"])
        #expect(EverydayLightsAsk.line(words: all) == "Everyday lights has 8 on, starting Battery, Rain, Timer, and Mic.")
        #expect(usual.boltCaption(at: 0) == "Moments")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Mic")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(EverydayLightsAsk.line(words: ["Battery", "Caps"]) == "Everyday lights has Battery and Caps on.")
        #expect(cards(EverydayLightsDraw.plan(words: [])) == ["Moments", "None"])
        #expect(EverydayLightsAsk.line(words: []) == "The everyday lights are off.")
        #expect(cards(EverydayLightsDraw.plan(words: ["Mic", "Battery"])) == ["Moments", "Can't"])
        #expect(EverydayLightsAsk.line(words: ["Glow"]) == "I can't read the everyday lights.")
    }

    @Test func theLevelLightsStayOffThisAsk() {
        #expect(EverydayLightsAsk.matches("which everyday lights"))
        #expect(EverydayLightsAsk.matches("Hey Zeus, which small moments?"))
        #expect(EverydayLightsAsk.matches("everyday light settings"))
        #expect(!EverydayLightsAsk.matches("which notch lights"))
        #expect(!EverydayLightsAsk.matches("how's the battery"))
        #expect(!EverydayLightsAsk.matches("how's the notch close"))
        #expect(!EverydayLightsAsk.matches("is caps lock on"))
    }
}
