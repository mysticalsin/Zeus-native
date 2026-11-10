import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Ticking views and pollers")
struct TickingTests {
    @Test func aViewTicksOnlyWhileShownUnpausedAndVisible() {
        #expect(TickRules.isRunning(appeared: true, paused: false, windowVisible: true))
        #expect(!TickRules.isRunning(appeared: true, paused: true, windowVisible: true))   // buddy hidden, halo off
        #expect(!TickRules.isRunning(appeared: true, paused: false, windowVisible: false)) // hidden menu-bar panel
        #expect(!TickRules.isRunning(appeared: false, paused: false, windowVisible: true))
    }

    @Test func hiddenWindowsStopTheTimerUntilVisibleAgain() {
        #expect(TickRules.timerInterval(requested: 1.0 / 24, windowVisible: false) == 1)
        #expect(abs(TickRules.timerInterval(requested: 1.0 / 24, windowVisible: true) - 1.0 / 24) < 1e-9)
        #expect(TickRules.clamped(0) >= 1.0 / 120)
        #expect(TickRules.clamped(.nan) == 1)
    }

    @Test func pollingIntervalsStayCheap() {
        #expect(TickRules.notificationPollSeconds >= 4)
        #expect(TickRules.wakeGateSeconds >= 1.5)
        #expect(TickRules.micCheckSeconds >= 4)
    }

    @Test func lightsShareTheMascotsBusyGrid() {
        #expect(NotchLights.frameInterval == 1 / LivingAvatar.busyFPS)
    }

    @MainActor @Test func pausedAndHiddenClocksHoldNoRunningTimer() {
        let clock = TickClock()
        clock.configure(interval: 1.0 / 24, paused: true)
        clock.appear()
        #expect(!clock.isRunning)
        clock.configure(interval: 1.0 / 24, paused: false)
        #expect(clock.isRunning)
        clock.disappear()
        #expect(!clock.isRunning)
    }

    @MainActor @Test func hiddenWindowStopsTheClockEntirely() {
        let clock = TickClock()
        var visible = true
        clock.windowProbe = { visible }
        clock.configure(interval: 1.0 / 24, paused: false)
        clock.appear()
        clock.recheckWindow()
        #expect(clock.isRunning)
        visible = false
        clock.recheckWindow()
        #expect(!clock.isRunning)
        #expect(HiddenTickWatch.isWatching)
        visible = true
        clock.recheckWindow()
        #expect(clock.isRunning)
        #expect(!HiddenTickWatch.isWatching)
        clock.disappear()
        #expect(!clock.isRunning)
    }

    @MainActor @Test func releasingRunningClockInvalidatesItsRunLoopTimer() throws {
        var clock: TickClock? = TickClock()
        clock?.configure(interval: 1.0 / 24, paused: false)
        clock?.appear()
        weak var releasedClock = clock
        // Observe the actual private timer without adding a production timer-inspection API.
        let timer = try #require(Mirror(reflecting: clock!).children
            .first(where: { $0.label == "timer" })?.value as? Timer)
        defer { timer.invalidate() }
        #expect(timer.isValid)
        clock = nil // Deliberately no disappear: the owner itself must release the scheduled work.
        #expect(releasedClock == nil)
        #expect(!timer.isValid)
    }

    @Test func idleMascotTicksSlowly() {
        #expect(LivingAvatar.restFPS <= 8)
        #expect(LivingAvatar.tickInterval(asleep: false, waking: false, state: .idle) >= 1.0 / 8)
        #expect(LivingAvatar.tickInterval(asleep: false, waking: false, state: .thinking) <= 1.0 / 24 + 0.001)
    }

    @Test func mirrorChangeStampTracksTheStoreAndItsLog() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-stamp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("db")
        #expect(NotificationMirror.changeStamp(url: db) == nil)
        try Data([1]).write(to: db)
        let first = try #require(NotificationMirror.changeStamp(url: db))
        let wal = URL(fileURLWithPath: db.path + "-wal")
        try Data([1]).write(to: wal)
        try FileManager.default.setAttributes([.modificationDate: first.addingTimeInterval(60)], ofItemAtPath: wal.path)
        #expect(try #require(NotificationMirror.changeStamp(url: db)) > first)
    }
}
