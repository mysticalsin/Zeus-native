import Foundation
import Testing
@testable import ZeusCore

@Suite("Keep awake rules box")
struct KeepAwakeRulesBoxTests {
    private func power(_ percent: Int?, charging: Bool = false, onBattery: Bool = true,
                       thermal: KeepAwakeRulesBox.Thermal = .nominal) -> KeepAwakeRulesBox.Power {
        KeepAwakeRulesBox.Power(batteryPercent: percent, isCharging: charging, onBattery: onBattery, thermal: thermal)
    }

    private func verdict(floor: Int = KeepAwakeRulesBox.defaultBatteryFloor,
                         endWhenHot: Bool = KeepAwakeRulesBox.defaultEndWhenHot,
                         hotLevel: KeepAwakeRulesBox.Thermal = KeepAwakeRulesBox.defaultHotLevel,
                         warnAt: Int = KeepAwakeRulesBox.defaultWarnAt,
                         power: KeepAwakeRulesBox.Power,
                         elapsed: TimeInterval = 60,
                         remaining: TimeInterval? = 600,
                         warned: Bool = false) -> KeepAwakeRulesBox.Verdict {
        KeepAwakeRulesBox.evaluate(batteryFloor: floor, endWhenHot: endWhenHot, hotLevel: hotLevel,
                                   warnAt: warnAt, power: power, elapsed: elapsed, remaining: remaining, warned: warned)
    }

    @Test func theDefaultsMatchTheSettingsFloors() {
        #expect(KeepAwakeRulesBox.defaultBatteryFloor == 10)
        #expect(KeepAwakeRulesBox.defaultEndWhenHot)
        #expect(KeepAwakeRulesBox.defaultHotLevel == .critical)
        #expect(KeepAwakeRulesBox.defaultWarnAt == 20)
        #expect(KeepAwakeRulesBox.floorChoices == [0, 5, 10, 15, 20])
    }

    @Test func aPowerSampleKeepsTheValuesItWasGiven() {
        let sample = power(40, charging: false, onBattery: true, thermal: .fair)
        #expect(sample.batteryPercent == 40)
        #expect(sample.isCharging == false)
        #expect(sample.onBattery == true)
        #expect(sample.thermal == .fair)
        let empty = KeepAwakeRulesBox.Power()
        #expect(empty.batteryPercent == nil)
        #expect(empty.isCharging == false)
        #expect(empty.onBattery == false)
        #expect(empty.thermal == .nominal)
    }

    @Test func thermalOrderIsNominalThenFairThenSeriousThenCritical() {
        #expect(KeepAwakeRulesBox.Thermal.nominal < .fair)
        #expect(KeepAwakeRulesBox.Thermal.fair < .serious)
        #expect(KeepAwakeRulesBox.Thermal.serious < .critical)
        #expect(!(KeepAwakeRulesBox.Thermal.critical < .nominal))
        #expect(KeepAwakeRulesBox.Thermal.critical >= .serious)
        #expect(KeepAwakeRulesBox.Thermal.nominal.rawValue == 0)
        #expect(KeepAwakeRulesBox.Thermal.critical.rawValue == 3)
    }

    @Test func timeUpWinsOverHeatAndOverALowBattery() {
        let drainedAndHot = power(5, thermal: .critical)
        #expect(verdict(power: drainedAndHot, remaining: 0) == .end(.timeUp))
        #expect(verdict(power: drainedAndHot, remaining: -3) == .end(.timeUp))
        #expect(verdict(power: power(nil, charging: true, onBattery: false, thermal: .critical), remaining: 0) == .end(.timeUp))
        #expect(KeepAwakeRulesBox.EndReason.timeUp.text == "Ended: time up")
    }

    @Test func aPositiveRemainderAndAnOpenSessionDoNotExpire() {
        #expect(verdict(power: power(80), remaining: 0.001) == .keepGoing)
        #expect(verdict(power: power(80), remaining: 1) == .keepGoing)
        #expect(verdict(power: power(80), remaining: nil) == .keepGoing)
        #expect(verdict(endWhenHot: false, power: power(5, thermal: .critical), remaining: nil) == .end(.lowBattery(5)))
    }

    @Test func elapsedDoesNotChangeTheVerdict() {
        let sample = power(80)
        #expect(verdict(power: sample, elapsed: 0, remaining: 30) == .keepGoing)
        #expect(verdict(power: sample, elapsed: -10, remaining: 30) == .keepGoing)
        #expect(verdict(power: sample, elapsed: 10_000, remaining: 30) == .keepGoing)
        #expect(verdict(power: power(4), elapsed: 0, remaining: 30) == .end(.lowBattery(4)))
        #expect(verdict(power: power(4), elapsed: 9_999, remaining: 30) == .end(.lowBattery(4)))
    }

    @Test func heatEndsAtTheChosenLevelEvenWhilePluggedIn() {
        #expect(verdict(power: power(80, thermal: .critical)) == .end(.tooHot(.critical)))
        #expect(verdict(power: power(80, thermal: .serious)) == .keepGoing)
        #expect(verdict(endWhenHot: false, power: power(80, thermal: .critical)) == .keepGoing)
        #expect(verdict(hotLevel: .serious, power: power(80, thermal: .serious)) == .end(.tooHot(.serious)))
        #expect(verdict(hotLevel: .serious, power: power(80, thermal: .fair)) == .keepGoing)
        #expect(verdict(hotLevel: .nominal, power: power(100, charging: true, onBattery: false, thermal: .nominal)) == .end(.tooHot(.nominal)))
        let charging = power(50, charging: true, onBattery: false, thermal: .critical)
        #expect(verdict(power: charging) == .end(.tooHot(.critical)))
        #expect(verdict(power: power(nil, thermal: .critical)) == .end(.tooHot(.critical)))
        #expect(KeepAwakeRulesBox.EndReason.tooHot(.fair).text == "Ended: Mac too hot")
    }

    @Test func theBatteryFloorEndsOnlyBelowTheLine() {
        #expect(verdict(power: power(9)) == .end(.lowBattery(9)))
        #expect(verdict(power: power(10)) == .warnLowBattery(10))
        #expect(verdict(floor: 15, power: power(14)) == .end(.lowBattery(14)))
        #expect(verdict(floor: 15, power: power(15)) == .warnLowBattery(15))
        #expect(verdict(floor: 0, power: power(0), warned: true) == .keepGoing)
        #expect(verdict(floor: 0, warnAt: 0, power: power(0)) == .keepGoing)
        #expect(verdict(power: power(0)) == .end(.lowBattery(0)))
        #expect(verdict(power: power(-4)) == .end(.lowBattery(-4)))
        #expect(verdict(power: power(100)) == .keepGoing)
        #expect(KeepAwakeRulesBox.EndReason.lowBattery(9).text == "Ended: battery 9%")
    }

    @Test func chargingACAndAMissingBatterySkipTheFloor() {
        #expect(verdict(power: power(3, charging: true, onBattery: true)) == .keepGoing)
        #expect(verdict(power: power(3, charging: false, onBattery: false)) == .keepGoing)
        #expect(verdict(power: power(nil, charging: false, onBattery: true)) == .keepGoing)
        #expect(verdict(power: power(15, charging: true, onBattery: true), warned: false) == .keepGoing)
        #expect(verdict(floor: 20, warnAt: 10, power: power(20)) == .keepGoing)
        #expect(verdict(floor: 20, warnAt: 10, power: power(12)) == .end(.lowBattery(12)))
    }

    @Test func theWarningFiresOnceAboveTheFloor() {
        #expect(verdict(power: power(21)) == .keepGoing)
        #expect(verdict(power: power(20)) == .warnLowBattery(20))
        #expect(verdict(power: power(11)) == .warnLowBattery(11))
        #expect(verdict(power: power(20), warned: true) == .keepGoing)
        #expect(verdict(warnAt: 0, power: power(15)) == .keepGoing)
        #expect(verdict(floor: 5, warnAt: 20, power: power(5)) == .warnLowBattery(5))
        #expect(verdict(floor: 5, warnAt: 20, power: power(4)) == .end(.lowBattery(4)))
    }

    @Test func floorLabelsRoundTripAndUnknownLabelsAreOff() {
        #expect(KeepAwakeRulesBox.floorChoices.map(KeepAwakeRulesBox.floorLabel) == ["Off", "5%", "10%", "15%", "20%"])
        for floor in KeepAwakeRulesBox.floorChoices {
            #expect(KeepAwakeRulesBox.floor(fromLabel: KeepAwakeRulesBox.floorLabel(floor)) == floor)
        }
        #expect(KeepAwakeRulesBox.floorLabel(0) == "Off")
        #expect(KeepAwakeRulesBox.floorLabel(-4) == "Off")
        #expect(KeepAwakeRulesBox.floorLabel(7) == "7%")
        #expect(KeepAwakeRulesBox.floorLabel(100) == "100%")
        #expect(KeepAwakeRulesBox.floor(fromLabel: "Off") == 0)
        #expect(KeepAwakeRulesBox.floor(fromLabel: "10%") == 10)
        #expect(KeepAwakeRulesBox.floor(fromLabel: "nonsense") == 0)
        #expect(KeepAwakeRulesBox.floor(fromLabel: "") == 0)
        #expect(KeepAwakeRulesBox.floor(fromLabel: "0%") == 0)
        #expect(KeepAwakeRulesBox.floor(fromLabel: "7%") == 0)
        #expect(KeepAwakeRulesBox.floor(fromLabel: " 10%") == 0)
        #expect(KeepAwakeRulesBox.floor(fromLabel: "off") == 0)
    }

    @Test func lengthLabelsCoverMinutesHoursAndIndefinitely() {
        #expect(KeepAwakeRulesBox.lengthLabel(nil) == "Indefinitely")
        #expect(KeepAwakeRulesBox.lengthLabel(0) == "0 minutes")
        #expect(KeepAwakeRulesBox.lengthLabel(15) == "15 minutes")
        #expect(KeepAwakeRulesBox.lengthLabel(59) == "59 minutes")
        #expect(KeepAwakeRulesBox.lengthLabel(60) == "1 hour")
        #expect(KeepAwakeRulesBox.lengthLabel(61) == "61 minutes")
        #expect(KeepAwakeRulesBox.lengthLabel(90) == "90 minutes")
        #expect(KeepAwakeRulesBox.lengthLabel(120) == "2 hours")
        #expect(KeepAwakeRulesBox.lengthLabel(180) == "3 hours")
        #expect(KeepAwakeRulesBox.lengthLabel(-60) == "-60 minutes")
        #expect(KeepAwakeRulesBox.lengthLabel(24 * 60) == "24 hours")
    }

    @Test func lengthParsingAcceptsOnlyThePresets() {
        #expect(KeepAwakeRulesBox.shortLengths == [15, 30, 60, 120])
        #expect(KeepAwakeRulesBox.longLengths == [240, 480, 1440])
        #expect(KeepAwakeRulesBox.allLengths.map(KeepAwakeRulesBox.lengthLabel) == [
            "15 minutes", "30 minutes", "1 hour", "2 hours", "4 hours", "8 hours", "24 hours", "Indefinitely"
        ])
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "15 minutes") == .some(15))
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "1 hour") == .some(60))
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "8 hours") == .some(480))
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "24 hours") == .some(1440))
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "Indefinitely") == .some(nil))
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "3 hours") == nil)
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "indefinitely") == nil)
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "1 hour ") == nil)
        #expect(KeepAwakeRulesBox.minutes(fromLabel: "") == nil)
    }

    @Test func countdownTextClampsAndSplitsAtOneHour() {
        #expect(KeepAwakeRulesBox.countdown(nil) == "On")
        #expect(KeepAwakeRulesBox.countdown(-1) == "0:00")
        #expect(KeepAwakeRulesBox.countdown(-3_600) == "0:00")
        #expect(KeepAwakeRulesBox.countdown(0) == "0:00")
        #expect(KeepAwakeRulesBox.countdown(0.9) == "0:00")
        #expect(KeepAwakeRulesBox.countdown(59) == "0:59")
        #expect(KeepAwakeRulesBox.countdown(59.9) == "0:59")
        #expect(KeepAwakeRulesBox.countdown(60) == "1:00")
        #expect(KeepAwakeRulesBox.countdown(60.9) == "1:00")
        #expect(KeepAwakeRulesBox.countdown(545) == "9:05")
        #expect(KeepAwakeRulesBox.countdown(3599) == "59:59")
        #expect(KeepAwakeRulesBox.countdown(3600) == "1:00:00")
        #expect(KeepAwakeRulesBox.countdown(4 * 3600 - 55) == "3:59:05")
        #expect(KeepAwakeRulesBox.countdown(25 * 3600 + 61) == "25:01:01")
    }
}
