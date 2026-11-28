import Testing
@testable import ZeusCore

struct BrightnessLevelDrawTests {
    private func cards(_ plan: BrightnessLevelDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aLevelDrawsThePercentThenBright() {
        let plan = BrightnessLevelDraw.plan(percent: 70)
        #expect(plan.map(cards) == ["Brightness", "70%", "Bright"])
        #expect(BrightnessLevelAsk.line(percent: 70) == "Brightness is at 70 percent.")
        #expect(BrightnessLevelAsk.line(percent: 12) == "Brightness is at 12 percent.")
        #expect(BrightnessLevelDraw.plan(percent: 12).map(cards) == ["Brightness", "12%", "Dim"])
        #expect(BrightnessLevelAsk.percent(of: 0.7) == 70)
        #expect(BrightnessLevelAsk.percent(of: 1) == 100)
        #expect(BrightnessLevelAsk.percent(of: .infinity) == nil)
        #expect(plan?.boltCaption(at: 0) == "Brightness")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "70%")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Bright")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(BrightnessLevelDraw.plan(percent: -1) == nil)
        #expect(BrightnessLevelDraw.plan(percent: 101) == nil)
    }

    @Test func aDarkScreenDrawsOffAndTheVolumeIsNotThisAsk() {
        let dark = BrightnessLevelDraw.plan(percent: 0)
        #expect(dark.map(cards) == ["Brightness", "Off"])
        #expect(BrightnessLevelAsk.line(percent: 0) == "The screen is dark.")
        #expect(dark?.boltCaption(at: ExplainBeatSchedule.gap) == "Off")
        #expect(dark?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(BrightnessLevelDraw.unread()) == ["Brightness", "Can't"])
        #expect(BrightnessLevelAsk.unread == "I can't read the brightness.")
        #expect(BrightnessLevelAsk.matches("what's the brightness"))
        #expect(BrightnessLevelAsk.matches("Hey Zeus, how bright is the screen?"))
        #expect(BrightnessLevelAsk.matches("how's the brightness"))
        #expect(BrightnessLevelAsk.matches("screen brightness"))
        #expect(!BrightnessLevelAsk.matches("what's the volume"))
        #expect(!BrightnessLevelAsk.matches("how loud is it"))
        #expect(!BrightnessLevelAsk.matches("what's my battery"))
        #expect(!BrightnessLevelAsk.matches("how many to-dos"))
        #expect(!BrightnessLevelAsk.matches("turn up the brightness"))
        #expect(!BrightnessLevelAsk.matches("keyboard brightness"))
    }
}
