import Foundation
import Testing
@testable import ZeusCore

@Suite struct MusicAwakeTests {
    private let rule = MusicAwakeRule()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func onBattery(_ percent: Int, thermal: KeepAwakeRules.Thermal = .nominal) -> KeepAwakeRules.Power {
        .init(batteryPercent: percent, isCharging: false, onBattery: true, thermal: thermal)
    }

    private func decide(enabled: Bool = true, isPlaying: Bool = true, lastPlayedAt: Date? = nil,
                        power: KeepAwakeRules.Power = .init(), rules: KeepAwakeRules = KeepAwakeRules()) -> MusicAwakeRule.Verdict {
        rule.decide(enabled: enabled, isPlaying: isPlaying, lastPlayedAt: lastPlayedAt, now: now, power: power, rules: rules)
    }

    @Test func graceIsTwentySeconds() {
        #expect(rule.grace == 20)
    }

    @Test func playingHolds() {
        #expect(decide() == .hold)
    }

    @Test func aPauseInsideTheGraceHolds() {
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(-19)) == .hold)
        #expect(decide(isPlaying: false, lastPlayedAt: now) == .hold)
    }

    @Test func beyondTheGraceReleases() {
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(-20)) == .release(.notPlaying))
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(-300)) == .release(.notPlaying))
    }

    @Test func neverPlayedReleases() {
        #expect(decide(isPlaying: false, lastPlayedAt: nil) == .release(.notPlaying))
    }

    @Test func aPlayTimeInTheFutureDoesNotHold() {
        // A clock set backwards must not keep the display on.
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(60)) == .release(.notPlaying))
    }

    @Test func offReleasesEvenWhilePlaying() {
        #expect(decide(enabled: false) == .release(.off))
        #expect(decide(enabled: false, isPlaying: false, lastPlayedAt: now) == .release(.off))
    }

    @Test func belowTheFloorOnBatteryReleasesWithThePercent() {
        #expect(decide(power: onBattery(9)) == .release(.lowBattery(9)))
        #expect(decide(power: onBattery(10)) == .hold)
    }

    @Test func chargingBelowTheFloorHolds() {
        let charging = KeepAwakeRules.Power(batteryPercent: 3, isCharging: true, onBattery: true)
        #expect(decide(power: charging) == .hold)
        let onAC = KeepAwakeRules.Power(batteryPercent: 3, isCharging: false, onBattery: false)
        #expect(decide(power: onAC) == .hold)
    }

    @Test func theHotLevelReleases() {
        #expect(decide(power: onBattery(80, thermal: .critical)) == .release(.tooHot))
        #expect(decide(power: .init(thermal: .critical)) == .release(.tooHot))
        #expect(decide(power: .init(thermal: .serious)) == .hold)
    }

    @Test func heatRuleOffIgnoresHeat() {
        let rules = KeepAwakeRules(endWhenHot: false)
        #expect(decide(power: .init(thermal: .critical), rules: rules) == .hold)
    }

    @Test func aFloorOfZeroNeverReleasesForBattery() {
        let rules = KeepAwakeRules(batteryFloor: 0)
        #expect(decide(power: onBattery(1), rules: rules) == .hold)
    }

    @Test func aMacWithNoBatteryHolds() {
        #expect(decide(power: .init(batteryPercent: nil, onBattery: true)) == .hold)
    }

    @Test func notPlayingWinsOverPowerReasons() {
        let verdict = decide(isPlaying: false, lastPlayedAt: nil, power: onBattery(3, thermal: .critical))
        #expect(verdict == .release(.notPlaying))
    }

    @Test func recoveredPowerHoldsAgain() {
        #expect(decide(power: onBattery(9)) == .release(.lowBattery(9)))
        #expect(decide(power: .init(batteryPercent: 9, isCharging: true, onBattery: true)) == .hold)
    }

    @Test func holdFlag() {
        #expect(MusicAwakeRule.Verdict.hold.holds)
        #expect(!MusicAwakeRule.Verdict.release(.off).holds)
    }
}
