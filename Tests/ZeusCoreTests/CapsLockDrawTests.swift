import Testing
@testable import ZeusCore

struct CapsLockDrawTests {
    private func cards(_ plan: CapsLockDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func capsLockOnDrawsOn() {
        let plan = CapsLockDraw.plan(on: true)
        #expect(cards(plan) == ["Caps", "On"])
        #expect(CapsLockAsk.line(on: true) == "Caps Lock is on.")
        #expect(plan.boltCaption(at: 0) == "Caps")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "On")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func capsLockOffStaysOffTheBrightnessAsk() {
        let plan = CapsLockDraw.plan(on: false)
        #expect(cards(plan) == ["Caps", "Off"])
        #expect(CapsLockAsk.line(on: false) == "Caps Lock is off.")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Off")
        #expect(CapsLockAsk.matches("is caps lock on"))
        #expect(CapsLockAsk.matches("Hey Zeus, what's my caps lock?"))
        #expect(CapsLockAsk.matches("capslock"))
        #expect(!CapsLockAsk.matches("how's the brightness"))
        #expect(!CapsLockAsk.matches("what's in front"))
        #expect(!CapsLockAsk.matches("what's the volume"))
        #expect(!CapsLockAsk.matches("how many clips"))
    }
}
