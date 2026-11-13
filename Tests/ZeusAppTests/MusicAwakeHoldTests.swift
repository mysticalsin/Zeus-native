import Foundation
import IOKit.pwr_mgt
import Testing
import ZeusCore
@testable import Zeus

/// Stands in for the clock, the power readings and the assertion so no real assertion is taken.
@MainActor private final class Rig {
    var now = Date(timeIntervalSince1970: 2_000_000)
    var power = KeepAwakeRules.Power()
    var rules = KeepAwakeRules()
    var created: [IOPMAssertionID] = []
    var released: [IOPMAssertionID] = []
    var nextID: IOPMAssertionID = 100
    var lastLease: TimeInterval = 0
    lazy var hold = MusicAwakeHold(
        monitor: nil,
        clock: { [unowned self] in self.now },
        power: { [unowned self] in self.power },
        rules: { [unowned self] in self.rules },
        create: { [unowned self] lease in
            self.lastLease = lease
            self.nextID += 1
            self.created.append(self.nextID)
            return self.nextID
        },
        release: { [unowned self] id in self.released.append(id) })

    /// Holds that are live right now.
    var live: [IOPMAssertionID] { created.filter { !released.contains($0) } }
}

@Suite @MainActor struct MusicAwakeHoldTests {
    @Test func playingWithTheSettingOnHoldsOneAssertionWithATwoMinuteLease() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        #expect(rig.live.isEmpty)
        rig.hold.setPlaying(true)
        #expect(rig.live.count == 1)
        #expect(rig.lastLease == 120)
        #expect(rig.hold.isHolding)
    }

    @Test func theSettingOffNeverHolds() {
        let rig = Rig()
        rig.hold.setPlaying(true)
        #expect(rig.created.isEmpty)
        #expect(!rig.hold.isHolding)
    }

    @Test func turningTheSettingOnDuringASongHoldsAtOnce() {
        let rig = Rig()
        rig.hold.setPlaying(true)
        rig.hold.setEnabled(true)
        #expect(rig.live.count == 1)
    }

    @Test func turningTheSettingOffReleasesAtOnce() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.hold.setEnabled(false)
        #expect(rig.live.isEmpty)
        #expect(!rig.hold.isHolding)
    }

    @Test func aPauseHoldsInsideTheGraceAndReleasesAfterIt() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.hold.setPlaying(false)
        #expect(rig.live.count == 1)
        rig.now.addTimeInterval(19)
        rig.hold.evaluate()
        #expect(rig.live.count == 1)
        rig.now.addTimeInterval(1.1)
        rig.hold.evaluate()
        #expect(rig.live.isEmpty)
    }

    @Test func resumingInsideTheGraceKeepsTheSameHold() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.hold.setPlaying(false)
        rig.now.addTimeInterval(10)
        rig.hold.setPlaying(true)
        #expect(rig.created.count == 1)
        #expect(rig.released.isEmpty)
    }

    @Test func theMinuteTickRenewsTheLeaseWithoutAGap() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        let first = rig.created[0]
        rig.now.addTimeInterval(60)
        rig.hold.evaluate(renewLease: true)
        #expect(rig.created.count == 2)
        #expect(rig.released == [first])
        #expect(rig.live == [rig.created[1]])
    }

    @Test func lowBatteryOnBatteryReleasesAndRecoveryHoldsAgain() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.power = .init(batteryPercent: 9, isCharging: false, onBattery: true)
        rig.hold.evaluate()
        #expect(rig.live.isEmpty)
        rig.power = .init(batteryPercent: 9, isCharging: true, onBattery: true)
        rig.hold.evaluate()
        #expect(rig.live.count == 1)
    }

    @Test func theHotLevelReleases() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.power = .init(thermal: .critical)
        rig.hold.evaluate()
        #expect(rig.live.isEmpty)
        rig.power = .init(thermal: .nominal)
        rig.hold.evaluate()
        #expect(rig.live.count == 1)
    }

    @Test func theKeepAwakeFloorSettingIsUsed() {
        let rig = Rig()
        rig.rules = KeepAwakeRules(batteryFloor: 0)
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.power = .init(batteryPercent: 2, isCharging: false, onBattery: true)
        rig.hold.evaluate()
        #expect(rig.live.count == 1)
    }
}
