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

    /// The mascot's frame-rate budget. Trade-off: the idle clip is 12 fps, so a resting mascot now ticks at 12 fps
    /// (it ticked at 6 before) so its own animation plays smoothly; that doubles its idle cost, and a closed notch
    /// is still the cheapest thing on screen. Nothing at rest goes above 12 fps, the listening and approval clips
    /// above their own rate (at most 24), and only the travel windows reach 60.
    @MainActor @Test func idleMascotTicksSlowly() {
        let atlas = MascotAtlasStore(directory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zeus/Avatar/Anim"))
        #expect(LivingAvatar.tickInterval(clipFPS: 12, travelling: false) == 1.0 / 12)
        #expect(LivingAvatar.tickInterval(clipFPS: 12, travelling: true) == 1.0 / 60)
        // At rest: at most 12 fps, asleep or awake.
        for mood in [MascotMotion.Mood.awake(.idle), .asleep] {
            let interval = LivingAvatar.tickInterval(for: MascotMotion.at(1, mood: mood, size: 22), atlas: atlas)
            #expect(interval >= 1.0 / 12 - 1e-9, "\(mood) ticks faster than 12 fps")
        }
        // Listening and approval: their clip's rate, never above 24.
        for state in [AvatarState.listening, .approval] {
            let motion = MascotMotion.at(1, mood: .awake(state), size: 22)
            let clip = atlas.clip(motion.pose.clipID)
            #expect(clip != nil)
            let interval = LivingAvatar.tickInterval(for: motion, atlas: atlas)
            #expect(interval >= 1.0 / 24 - 1e-9)
            #expect(abs(interval - 1.0 / Double(clip?.fps ?? 12)) < 1e-9)
        }
        // Over a long run of every state, only a travel window is faster than 24 fps.
        for state in AvatarState.allCases {
            for t in stride(from: 0.0, to: 80, by: 0.05) {
                let motion = MascotMotion.at(t, mood: .awake(state), size: 22)
                let interval = LivingAvatar.tickInterval(for: motion, atlas: atlas)
                if interval < 1.0 / 24 - 1e-9 { #expect(motion.travelling && interval == 1.0 / 60, "\(state) at \(t)") }
            }
        }
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
