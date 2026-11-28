import Testing
@testable import ZeusCore

struct BatteryDrawTests {
    private func cards(_ plan: BatteryDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aChargeDrawsBatteryThenTheStateThenThePercent() {
        let charging = BatteryDraw.plan(level: 80, state: .charging)
        #expect(charging.map(cards) == ["Battery", "Charging", "80 percent"])
        #expect(BatteryAsk.line(level: 80, state: .charging) == "Charging, 80 percent.")
        #expect(charging?.boltCaption(at: 0) == "Battery")
        #expect(charging?.boltCaption(at: ExplainBeatSchedule.gap) == "Charging")
        #expect(charging?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "80 percent")
        #expect(charging?.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(charging?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        let low = BatteryDraw.plan(level: 12, state: BatteryAsk.state(level: 12, charging: false, pluggedIn: false))
        #expect(low.map(cards) == ["Battery", "Low", "12 percent"])
        #expect(BatteryAsk.line(level: 12, state: .low) == "Battery is low, 12 percent.")
        #expect(BatteryDraw.plan(level: -1, state: .onBattery) == nil)
        #expect(BatteryDraw.plan(level: 101, state: .charging) == nil)
    }

    @Test func noBatteryDrawsNoneAndAKeepAwakeAskIsNotThis() {
        let idle = BatteryDraw.none()
        #expect(cards(idle) == ["Battery", "None"])
        #expect(idle.boltCaption(at: ExplainBeatSchedule.gap) == "None")
        #expect(BatteryAsk.none == "This Mac has no battery.")
        #expect(BatteryAsk.state(level: 100, charging: false, pluggedIn: true) == .pluggedIn)
        #expect(BatteryAsk.matches("what's my battery"))
        #expect(BatteryAsk.matches("Hey Zeus, how's my battery?"))
        #expect(!BatteryAsk.matches("keep awake"))
        #expect(!BatteryAsk.matches("what's the weather"))
        #expect(!BatteryAsk.matches("start focus"))
    }
}
