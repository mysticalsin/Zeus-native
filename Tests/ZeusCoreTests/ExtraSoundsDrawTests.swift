import Testing
@testable import ZeusCore

struct ExtraSoundsDrawTests {
    private func cards(_ plan: ExtraSoundsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func fourSoundsFollowExtra() {
        let usual = ExtraSoundsDraw.plan(timer: "On", fail: "On", start: "Off", loop: "Off")
        #expect(cards(usual) == ["Extra", "Timer: On", "Fail: On", "Start: Off", "Loop: Off"])
        #expect(ExtraSoundsAsk.line(timer: "On", fail: "On", start: "Off", loop: "Off") == "Timer alarms are on, the failure sound is on, the start chime is off, and the working loop is off.")
        #expect(usual.boltCaption(at: 0) == "Extra")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Loop: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(ExtraSoundsAsk.line(timer: "Off", fail: "Off", start: "On", loop: "On") == "Timer alarms are off, the failure sound is off, the start chime is on, and the working loop is on.")
        #expect(cards(ExtraSoundsDraw.plan(timer: "Off", fail: "On", start: "Off", loop: "On")) == ["Extra", "Timer: Off", "Fail: On", "Start: Off", "Loop: On"])
        #expect(cards(ExtraSoundsDraw.plan(timer: "Maybe", fail: "On", start: "Off", loop: "Off")) == ["Extra", "Can't"])
        #expect(ExtraSoundsAsk.line(timer: "On", fail: "Yes", start: "Off", loop: "Off") == "I can't read the extra sounds.")
    }

    @Test func cueStylesStayOffThisAsk() {
        #expect(ExtraSoundsAsk.matches("which extra sounds"))
        #expect(ExtraSoundsAsk.matches("Hey Zeus, are timer alarms on?"))
        #expect(ExtraSoundsAsk.matches("extra sound settings"))
        #expect(!ExtraSoundsAsk.matches("which cue sounds"))
        #expect(!ExtraSoundsAsk.matches("which events play a sound"))
        #expect(!ExtraSoundsAsk.matches("which voice cues"))
        #expect(!ExtraSoundsAsk.matches("which voice permissions"))
    }
}
