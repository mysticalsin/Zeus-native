import Foundation
import Testing
@testable import ZeusCore

@Suite struct KeepAwakeRulesTests {
    private let rules = KeepAwakeRules()

    private func onBattery(_ percent: Int, thermal: KeepAwakeRules.Thermal = .nominal) -> KeepAwakeRules.Power {
        .init(batteryPercent: percent, isCharging: false, onBattery: true, thermal: thermal)
    }

    private func verdict(_ power: KeepAwakeRules.Power, remaining: TimeInterval? = 600, warned: Bool = false,
                         rules: KeepAwakeRules? = nil) -> KeepAwakeRules.Verdict {
        (rules ?? self.rules).evaluate(power, elapsed: 60, remaining: remaining, warned: warned)
    }

    @Test func defaults() {
        #expect(rules.batteryFloor == 10)
        #expect(rules.endWhenHot)
        #expect(rules.hotLevel == .critical)
        #expect(rules.warnAt == 20)
    }

    @Test func endsBelowTheBatteryFloor() {
        #expect(verdict(onBattery(9)) == .end(.lowBattery(9)))
        #expect(verdict(onBattery(10)) == .warnLowBattery(10))
        #expect(KeepAwakeRules.EndReason.lowBattery(9).text == "Ended: battery 9%")
    }

    @Test func chargingOrACOverridesTheFloor() {
        let charging = KeepAwakeRules.Power(batteryPercent: 3, isCharging: true, onBattery: true)
        #expect(verdict(charging) == .keepGoing)
        let onAC = KeepAwakeRules.Power(batteryPercent: 3, isCharging: false, onBattery: false)
        #expect(verdict(onAC) == .keepGoing)
    }

    @Test func noBatteryNeverEnds() {
        #expect(verdict(.init(batteryPercent: nil, onBattery: true)) == .keepGoing)
    }

    @Test func floorIsConfigurableAndCanBeOff() {
        let fifteen = KeepAwakeRules(batteryFloor: 15)
        #expect(verdict(onBattery(14), rules: fifteen) == .end(.lowBattery(14)))
        #expect(verdict(onBattery(15), rules: fifteen) == .warnLowBattery(15))
        let off = KeepAwakeRules(batteryFloor: 0)
        #expect(verdict(onBattery(1), warned: true, rules: off) == .keepGoing)
    }

    @Test func endsAtCriticalHeat() {
        #expect(verdict(onBattery(80, thermal: .critical)) == .end(.tooHot(.critical)))
        #expect(verdict(onBattery(80, thermal: .serious)) == .keepGoing)
        #expect(KeepAwakeRules.EndReason.tooHot(.critical).text == "Ended: Mac too hot")
    }

    @Test func heatIsConfigurable() {
        let off = KeepAwakeRules(endWhenHot: false)
        #expect(verdict(onBattery(80, thermal: .critical), rules: off) == .keepGoing)
        let stricter = KeepAwakeRules(hotLevel: .serious)
        #expect(verdict(onBattery(80, thermal: .serious), rules: stricter) == .end(.tooHot(.serious)))
        #expect(verdict(onBattery(80, thermal: .fair), rules: stricter) == .keepGoing)
    }

    @Test func heatEndsEvenWhileCharging() {
        let hot = KeepAwakeRules.Power(batteryPercent: 50, isCharging: true, onBattery: false, thermal: .critical)
        #expect(verdict(hot) == .end(.tooHot(.critical)))
    }

    @Test func timeUp() {
        #expect(verdict(onBattery(80), remaining: 0) == .end(.timeUp))
        #expect(verdict(onBattery(80), remaining: -3) == .end(.timeUp))
        #expect(verdict(onBattery(80), remaining: 1) == .keepGoing)
        // Open-ended sessions have no remaining time and never run out.
        #expect(verdict(onBattery(80), remaining: nil) == .keepGoing)
    }

    @Test func timeUpWinsOverHeatAndHeatOverBattery() {
        #expect(verdict(onBattery(5, thermal: .critical), remaining: 0) == .end(.timeUp))
        #expect(verdict(onBattery(5, thermal: .critical)) == .end(.tooHot(.critical)))
    }

    @Test func warnsOnceAtTwentyPercent() {
        #expect(verdict(onBattery(21)) == .keepGoing)
        #expect(verdict(onBattery(20)) == .warnLowBattery(20))
        #expect(verdict(onBattery(11)) == .warnLowBattery(11))
        #expect(verdict(onBattery(20), warned: true) == .keepGoing)
        let charging = KeepAwakeRules.Power(batteryPercent: 15, isCharging: true, onBattery: true)
        #expect(verdict(charging) == .keepGoing)
        #expect(verdict(onBattery(15), rules: KeepAwakeRules(warnAt: 0)) == .keepGoing)
    }

    @Test func floorLabelsRoundTrip() {
        #expect(KeepAwakeRules.floorChoices.map(KeepAwakeRules.floorLabel) == ["Off", "5%", "10%", "15%", "20%"])
        for floor in KeepAwakeRules.floorChoices {
            #expect(KeepAwakeRules.floor(fromLabel: KeepAwakeRules.floorLabel(floor)) == floor)
        }
        #expect(KeepAwakeRules.floor(fromLabel: "nonsense") == 0)
    }

    @Test func lengthsIncludeLongPresetsAndIndefinitely() {
        #expect(KeepAwakeLength.all.map(KeepAwakeLength.label) == ["15 minutes", "30 minutes", "1 hour", "2 hours", "4 hours", "8 hours", "24 hours", "Indefinitely"])
        #expect(KeepAwakeLength.minutes(fromLabel: "8 hours") == .some(480))
        #expect(KeepAwakeLength.minutes(fromLabel: "Indefinitely") == .some(nil))
        #expect(KeepAwakeLength.minutes(fromLabel: "3 hours") == nil)
    }

    @Test func countdownText() {
        #expect(KeepAwakeLength.countdown(545) == "9:05")
        #expect(KeepAwakeLength.countdown(4 * 3600 - 55) == "3:59:05")
        #expect(KeepAwakeLength.countdown(nil) == "On")
        #expect(KeepAwakeLength.countdown(-1) == "0:00")
    }
}
