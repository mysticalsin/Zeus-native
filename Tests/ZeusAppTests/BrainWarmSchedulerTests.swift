import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor @Suite struct BrainWarmSchedulerTests {
    private func scheduler(clock: Box) -> (BrainWarmScheduler, Log) {
        let log = Log()
        let scheduler = BrainWarmScheduler()
        scheduler.now = { clock.date }
        scheduler.warm = { targets in log.calls.append(targets) }
        return (scheduler, log)
    }

    final class Box { var date = Date(timeIntervalSince1970: 2_000_000) }
    final class Log { var calls: [Set<BrainWarmPlan.Target>] = [] }

    @Test func doesNothingUntilZeusIsUsed() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        await scheduler.tick()
        #expect(log.calls.isEmpty)
    }

    @Test func warmsAfterActivityThenWaitsForTheNextInterval() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        scheduler.noteActivity()
        await scheduler.tick()
        #expect(log.calls == [[.localModel, .cloudConnection]])
        clock.date.addTimeInterval(60)
        await scheduler.tick()
        #expect(log.calls.count == 1, "too soon to ping again")
        clock.date.addTimeInterval(BrainWarmPlan.cloudInterval)
        scheduler.noteActivity()
        await scheduler.tick()
        #expect(log.calls.last == [.cloudConnection])
    }

    @Test func wakeForcesBothTargets() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        await scheduler.tick(forced: true)
        #expect(log.calls == [[.localModel, .cloudConnection]])
    }

    @Test func stopsPingingOnceZeusGoesQuiet() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        scheduler.noteActivity()
        await scheduler.tick()
        clock.date.addTimeInterval(BrainWarmPlan.activeWindow + 600)
        await scheduler.tick()
        #expect(log.calls.count == 1)
    }
}
