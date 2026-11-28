import Testing
@testable import ZeusCore

struct VolumeLevelDrawTests {
    private func cards(_ plan: VolumeLevelDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aLevelDrawsThePercentThenOn() {
        let plan = VolumeLevelDraw.plan(percent: 40, muted: false)
        #expect(plan.map(cards) == ["Volume", "40%", "On"])
        #expect(VolumeLevelAsk.line(percent: 40, muted: false) == "Volume is at 40 percent.")
        #expect(VolumeLevelAsk.line(percent: 1, muted: false) == "Volume is at 1 percent.")
        #expect(VolumeLevelAsk.percent(of: 0.4) == 40)
        #expect(VolumeLevelAsk.percent(of: 1) == 100)
        #expect(VolumeLevelAsk.percent(of: .infinity) == nil)
        #expect(plan?.boltCaption(at: 0) == "Volume")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "40%")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "On")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(VolumeLevelDraw.plan(percent: -1, muted: false) == nil)
        #expect(VolumeLevelDraw.plan(percent: 101, muted: false) == nil)
    }

    @Test func mutedDrawsMutedAndAChangeIsNotThisAsk() {
        let muted = VolumeLevelDraw.plan(percent: 40, muted: true)
        #expect(muted.map(cards) == ["Volume", "Muted"])
        #expect(VolumeLevelAsk.line(percent: 40, muted: true) == "Volume is muted.")
        #expect(VolumeLevelAsk.line(percent: 0, muted: false) == "Volume is muted.")
        #expect(muted?.boltCaption(at: ExplainBeatSchedule.gap) == "Muted")
        #expect(muted?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(VolumeLevelDraw.unread()) == ["Volume", "Can't"])
        #expect(VolumeLevelAsk.unread == "I can't read the volume.")
        #expect(VolumeLevelAsk.matches("what's the volume"))
        #expect(VolumeLevelAsk.matches("Hey Zeus, how loud is it?"))
        #expect(VolumeLevelAsk.matches("how's the volume"))
        #expect(VolumeLevelAsk.matches("volume level"))
        #expect(!VolumeLevelAsk.matches("volume up"))
        #expect(!VolumeLevelAsk.matches("louder"))
        #expect(!VolumeLevelAsk.matches("mute"))
        #expect(!VolumeLevelAsk.matches("set the volume to 40"))
        #expect(!VolumeLevelAsk.matches("volume 40"))
        #expect(!VolumeLevelAsk.matches("what's my battery"))
        #expect(!VolumeLevelAsk.matches("how many to-dos"))
    }
}
