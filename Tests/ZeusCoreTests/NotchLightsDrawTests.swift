import Testing
@testable import ZeusCore

struct NotchLightsDrawTests {
    private func cards(_ plan: NotchLightsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theLightsThatAreOnFollowLights() {
        let all = NotchLightsDraw.plan(words: ["Volume", "Brightness", "Keyboard"])
        #expect(cards(all) == ["Lights", "Volume", "Brightness", "Keyboard"])
        #expect(NotchLightsAsk.line(words: ["Volume", "Brightness", "Keyboard"]) == "The notch lights volume, brightness, and the keyboard.")
        #expect(all.boltCaption(at: 0) == "Lights")
        #expect(all.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Keyboard")
        #expect(all.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(cards(NotchLightsDraw.plan(words: [])) == ["Lights", "None"])
        #expect(NotchLightsAsk.line(words: []) == "The notch lights are off.")
        #expect(NotchLightsAsk.line(words: ["Volume"]) == "The notch lights volume.")
        #expect(cards(NotchLightsDraw.plan(words: ["Keyboard", "Volume"])) == ["Lights", "Can't"])
        #expect(NotchLightsAsk.line(words: ["Lamp"]) == "I can't read the notch lights.")
    }

    @Test func theHaloAndTheVolumeLevelStayOffThisAsk() {
        #expect(NotchLightsAsk.matches("which notch lights"))
        #expect(NotchLightsAsk.matches("Hey Zeus, how's the notch lights?"))
        #expect(NotchLightsAsk.matches("notch lights"))
        #expect(!NotchLightsAsk.matches("what's the halo"))
        #expect(!NotchLightsAsk.matches("what's the notch light"))
        #expect(!NotchLightsAsk.matches("what's the volume"))
        #expect(!NotchLightsAsk.matches("how's the brightness"))
        #expect(!NotchLightsAsk.matches("what's on home"))
    }
}
