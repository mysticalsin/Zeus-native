import Foundation
import IOKit.pwr_mgt
import Testing
import ZeusCore
@testable import Zeus

/// One callback the hold asked the scheduler for. Firing it by hand stands in for the clock running out.
private final class Scheduled {
    let delay: TimeInterval
    let repeats: Bool
    let fire: @MainActor () -> Void
    var cancelled = false

    init(delay: TimeInterval, repeats: Bool, fire: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.repeats = repeats
        self.fire = fire
    }
}

/// Stands in for the clock, the power readings, the assertion and the timers so no real assertion
/// is taken and no real timer runs. Pass a real `PowerMonitor` to test the power watch.
@MainActor private final class Rig {
    var now = Date(timeIntervalSince1970: 2_000_000)
    var power = KeepAwakeRules.Power()
    var rules = KeepAwakeRules()
    var created: [IOPMAssertionID] = []
    var released: [IOPMAssertionID] = []
    /// Every create and release in order, so a test can see what came first.
    var events: [String] = []
    var scheduled: [Scheduled] = []
    var nextID: IOPMAssertionID = 100
    var lastLease: TimeInterval = 0
    private let monitor: PowerMonitor?

    init(monitor: PowerMonitor? = nil) {
        self.monitor = monitor
    }

    lazy var hold = MusicAwakeHold(
        monitor: monitor,
        clock: { [unowned self] in self.now },
        power: { [unowned self] in self.power },
        rules: { [unowned self] in self.rules },
        create: { [unowned self] lease in
            self.lastLease = lease
            self.nextID += 1
            self.created.append(self.nextID)
            self.events.append("create \(self.nextID)")
            return self.nextID
        },
        release: { [unowned self] id in
            self.released.append(id)
            self.events.append("release \(id)")
        },
        schedule: { [unowned self] delay, repeats, fire in
            let item = Scheduled(delay: delay, repeats: repeats, fire: fire)
            self.scheduled.append(item)
            return { item.cancelled = true }
        })

    /// Holds that are live right now.
    var live: [IOPMAssertionID] { created.filter { !released.contains($0) } }
    /// Timers that were asked for and not cancelled.
    var liveTimers: [Scheduled] { scheduled.filter { !$0.cancelled } }
    var renewTimers: [Scheduled] { liveTimers.filter { $0.repeats } }
    var graceTimers: [Scheduled] { liveTimers.filter { !$0.repeats } }
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

    // MARK: Timers

    @Test func holdingKeepsOneRepeatingMinuteTimerAndReleasingRemovesIt() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        #expect(rig.liveTimers.isEmpty)
        rig.hold.setPlaying(true)
        #expect(rig.renewTimers.count == 1)
        #expect(rig.renewTimers.first?.delay == 60)
        rig.hold.evaluate()
        #expect(rig.scheduled.filter { $0.repeats }.count == 1, "the minute timer is not scheduled twice")
        rig.hold.setEnabled(false)
        #expect(rig.liveTimers.isEmpty)
    }

    @Test func aLowBatteryReleaseAlsoRemovesTheMinuteTimer() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.power = .init(batteryPercent: 9, isCharging: false, onBattery: true)
        rig.hold.evaluate()
        #expect(rig.renewTimers.isEmpty)
    }

    @Test func theMinuteTimerTakesANewAssertionBeforeReleasingTheOldOne() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.now.addTimeInterval(60)
        rig.renewTimers[0].fire()
        #expect(rig.events == ["create 101", "create 102", "release 101"])
        #expect(rig.live == [102])
        #expect(rig.renewTimers.count == 1)
    }

    @Test func aPauseSchedulesOneGraceTimerThatReleasesWhenItFires() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        #expect(rig.graceTimers.isEmpty)
        rig.hold.setPlaying(false)
        #expect(rig.graceTimers.count == 1)
        let grace = rig.graceTimers[0]
        #expect(grace.delay > 19.9 && grace.delay < 20.2)
        rig.now.addTimeInterval(grace.delay)
        grace.fire()
        #expect(rig.live.isEmpty)
        #expect(rig.liveTimers.isEmpty)
    }

    @Test func resumingOrTurningTheSettingOffCancelsTheGraceTimer() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.hold.setPlaying(false)
        rig.hold.setPlaying(true)
        #expect(rig.graceTimers.isEmpty)
        rig.hold.setPlaying(false)
        #expect(rig.graceTimers.count == 1)
        rig.hold.setEnabled(false)
        #expect(rig.graceTimers.isEmpty)
    }

    @Test func invalidateCancelsTheTimersAndReleasesTheAssertion() {
        let rig = Rig()
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.hold.setPlaying(false)
        #expect(rig.liveTimers.count == 2)
        rig.hold.invalidate()
        #expect(rig.liveTimers.isEmpty)
        #expect(rig.live.isEmpty)
        #expect(!rig.hold.isHolding)
    }

    // MARK: Power watch

    @Test func aLowBatteryReleaseKeepsWatchingAndChargingTakesTheHoldBack() {
        let monitor = PowerMonitor()
        let rig = Rig(monitor: monitor)
        defer { rig.hold.invalidate() }
        rig.hold.setEnabled(true)
        rig.power = .init(batteryPercent: 9, isCharging: false, onBattery: true)
        rig.hold.setPlaying(true)
        #expect(rig.live.isEmpty)
        #expect(monitor.isRunning, "released for the battery, but still watching for power to recover")
        rig.power = .init(batteryPercent: 9, isCharging: true, onBattery: true)
        monitor.onMusicChange()
        #expect(rig.live.count == 1)
    }

    @Test func aHotReleaseKeepsWatchingAndCoolingTakesTheHoldBack() {
        let monitor = PowerMonitor()
        let rig = Rig(monitor: monitor)
        defer { rig.hold.invalidate() }
        rig.hold.setEnabled(true)
        rig.power = .init(thermal: .critical)
        rig.hold.setPlaying(true)
        #expect(rig.live.isEmpty)
        #expect(monitor.isRunning)
        rig.power = .init(thermal: .nominal)
        monitor.onMusicChange()
        #expect(rig.live.count == 1)
    }

    @Test func thePowerMonitorRunsOnlyWhileAHoldCouldBeWanted() {
        let monitor = PowerMonitor()
        let rig = Rig(monitor: monitor)
        defer { rig.hold.invalidate() }
        rig.hold.setEnabled(true)
        #expect(!monitor.isRunning, "setting on, nothing playing")
        rig.hold.setPlaying(true)
        #expect(monitor.isRunning)
        rig.hold.setPlaying(false)
        #expect(monitor.isRunning, "a pause inside the grace still watches")
        let grace = rig.graceTimers[0]
        rig.now.addTimeInterval(grace.delay)
        grace.fire()
        #expect(!monitor.isRunning, "the grace is over")
    }

    @Test func turningTheSettingOffStopsThePowerMonitor() {
        let monitor = PowerMonitor()
        let rig = Rig(monitor: monitor)
        defer { rig.hold.invalidate() }
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        #expect(monitor.isRunning)
        rig.hold.setEnabled(false)
        #expect(!monitor.isRunning)
    }

    @Test func invalidateStopsThePowerMonitor() {
        let monitor = PowerMonitor()
        let rig = Rig(monitor: monitor)
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.hold.invalidate()
        #expect(!monitor.isRunning)
    }

    @Test func theMusicHoldLeavesTheKeepAwakeSessionsReadingsOn() {
        let monitor = PowerMonitor()
        monitor.start(for: .keepAwake)
        defer { monitor.stop(for: .keepAwake) }
        let rig = Rig(monitor: monitor)
        rig.hold.setEnabled(true)
        rig.hold.setPlaying(true)
        rig.hold.setEnabled(false)
        #expect(monitor.isRunning, "a session is still using the readings")
    }
}
