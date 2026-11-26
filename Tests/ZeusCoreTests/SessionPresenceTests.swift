import Foundation
import Testing
@testable import ZeusCore

@Suite("Session presence")
struct SessionPresenceTests {
    private func locked(onConsole: Bool = true) -> SessionFacts {
        SessionFacts(screenLocked: true, onConsole: onConsole)
    }

    private func unlocked(onConsole: Bool = true) -> SessionFacts {
        SessionFacts(screenLocked: false, onConsole: onConsole)
    }

    @Test func aFreshValueShowsNothingAndTreatsTheOwnerAsAbsent() {
        let awake = SessionPresence(displaysAwake: true)
        #expect(awake.reading == .unknown)
        #expect(awake.hint == .none)
        #expect(awake.onConsole == false)
        #expect(awake.displaysAwake == true)
        #expect(awake.screensaver == false)
        #expect(awake.systemAsleep == false)
        #expect(awake.settleLeft == 0)
        #expect(awake.lockSurfaceMayShow == false)
        #expect(awake.ownerPresent == false)

        let asleep = SessionPresence(displaysAwake: false)
        #expect(asleep.displaysAwake == false)
        #expect(asleep.lockSurfaceMayShow == false)
        #expect(asleep.ownerPresent == false)
    }

    @Test func aLockNoticeAloneNeverShowsTheSurface() {
        var presence = SessionPresence(displaysAwake: true)
        let effects = presence.reduce(.lockNotified)
        #expect(effects == [.readSession(after: 0)])
        #expect(presence.hint == .locked)
        #expect(presence.reading == .unknown)
        #expect(presence.settleLeft == SessionPresence.settleDelays.count)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.ownerPresent == false)
    }

    @Test func aSettleReadThatFindsTheLockShowsTheSurface() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.lockNotified)
        let early = presence.reduce(.sessionRead(unlocked()))
        #expect(presence.reading == .unlocked)
        #expect(presence.hint == .locked)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.ownerPresent == false)
        #expect(early == [.readSession(after: 0.5)])
        #expect(presence.settleLeft == 2)

        let found = presence.reduce(.sessionRead(locked()))
        #expect(presence.reading == .locked)
        #expect(presence.onConsole == true)
        #expect(presence.lockSurfaceMayShow == true)
        #expect(presence.ownerPresent == false)
        #expect(found == [.readSession(after: SessionPresence.watchSeconds)])
    }

    @Test func theSettleRunStopsAfterThreeReads() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.lockNotified)
        for delay in SessionPresence.settleDelays {
            let effects = presence.reduce(.sessionRead(unlocked()))
            #expect(effects == [.readSession(after: delay)])
            #expect(presence.lockSurfaceMayShow == false)
            #expect(presence.ownerPresent == false)
        }
        #expect(presence.settleLeft == 0)
        let stopped = presence.reduce(.sessionRead(unlocked()))
        #expect(stopped == [])
        #expect(presence.settleLeft == 0)
        #expect(presence.hint == .locked)
        #expect(presence.reading == .unlocked)
    }

    @Test func aDisplayWakeWhileLockedKeepsTheOwnerAbsent() {
        var presence = SessionPresence(displaysAwake: false)
        let read = presence.reduce(.sessionRead(locked()))
        #expect(read == [])
        #expect(presence.reading == .locked)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.ownerPresent == false)

        let woke = presence.reduce(.displaysWoke)
        #expect(woke == [.readSession(after: 0)])
        #expect(presence.displaysAwake == true)
        #expect(presence.reading == .locked)
        #expect(presence.ownerPresent == false)
        #expect(presence.lockSurfaceMayShow == true)
    }

    @Test func anUnlockNoticeKeepsTheOwnerAbsentWhileTheReadingStaysLocked() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked()))
        #expect(presence.lockSurfaceMayShow == true)
        let effects = presence.reduce(.unlockNotified)
        #expect(effects == [.readSession(after: 0)])
        #expect(presence.hint == .unlocked)
        #expect(presence.reading == .locked)
        #expect(presence.ownerPresent == false)
        #expect(presence.lockSurfaceMayShow == true)
    }

    @Test func aWatchReadAfterALockFindsTheOwnerWithoutAnUnlockNotice() {
        var presence = SessionPresence(displaysAwake: true)
        let watch = presence.reduce(.sessionRead(locked()))
        #expect(watch == [.readSession(after: SessionPresence.watchSeconds)])
        #expect(presence.ownerPresent == false)

        let back = presence.reduce(.sessionRead(unlocked()))
        #expect(presence.reading == .unlocked)
        #expect(presence.hint == .none)
        #expect(presence.screensaver == false)
        #expect(presence.ownerPresent == true)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(back == [])
    }

    @Test func returningToTheConsoleClearsALockedHintWithoutAnUnlockNotice() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.lockNotified)
        _ = presence.reduce(.sessionRead(unlocked()))
        #expect(presence.hint == .locked)
        #expect(presence.reading == .unlocked)
        #expect(presence.ownerPresent == false)

        let effects = presence.reduce(.sessionBecameActive)
        #expect(effects == [.readSession(after: 0)])
        #expect(presence.hint == .none)
        #expect(presence.onConsole == true)
        #expect(presence.reading == .unlocked)
        #expect(presence.ownerPresent == true)
    }

    @Test func becomingActiveWhileTheReadingIsLockedDoesNotMakeTheOwnerPresent() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked(onConsole: false)))
        #expect(presence.onConsole == false)
        #expect(presence.ownerPresent == false)
        _ = presence.reduce(.sessionBecameActive)
        #expect(presence.onConsole == true)
        #expect(presence.reading == .locked)
        #expect(presence.ownerPresent == false)
        #expect(presence.lockSurfaceMayShow == true)
    }

    @Test func anUnlockHintSurvivesBecomingActive() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.unlockNotified)
        _ = presence.reduce(.sessionBecameActive)
        #expect(presence.hint == .unlocked)
        #expect(presence.onConsole == true)
        #expect(presence.reading == .unknown)
        #expect(presence.ownerPresent == false)
    }

    @Test func aLockedReadOffTheConsoleDoesNotShowTheSurface() {
        var presence = SessionPresence(displaysAwake: true)
        let effects = presence.reduce(.sessionRead(locked(onConsole: false)))
        #expect(presence.reading == .locked)
        #expect(presence.onConsole == false)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.ownerPresent == false)
        #expect(effects == [.readSession(after: SessionPresence.watchSeconds)])
    }

    @Test func anUnlockedReadOffTheConsoleLeavesTheOwnerAbsent() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked()))
        let effects = presence.reduce(.sessionRead(unlocked(onConsole: false)))
        #expect(presence.reading == .unlocked)
        #expect(presence.onConsole == false)
        #expect(presence.hint == .none)
        #expect(presence.ownerPresent == false)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(effects == [])
    }

    @Test func theFirstUnlockedReadOnTheConsoleMakesTheOwnerPresent() {
        var presence = SessionPresence(displaysAwake: true)
        let effects = presence.reduce(.sessionRead(unlocked()))
        #expect(effects == [])
        #expect(presence.reading == .unlocked)
        #expect(presence.onConsole == true)
        #expect(presence.hint == .none)
        #expect(presence.ownerPresent == true)
        #expect(presence.lockSurfaceMayShow == false)
    }

    @Test func theWatchRunsOnlyWhileLockedLitAndAwake() {
        var lit = SessionPresence(displaysAwake: true)
        #expect(lit.reduce(.sessionRead(locked())) == [.readSession(after: SessionPresence.watchSeconds)])

        var dark = SessionPresence(displaysAwake: false)
        #expect(dark.reduce(.sessionRead(locked())) == [])
        #expect(dark.lockSurfaceMayShow == false)

        var sleeping = SessionPresence(displaysAwake: true)
        #expect(sleeping.reduce(.willSleep) == [.readSession(after: 0)])
        #expect(sleeping.reduce(.sessionRead(locked())) == [])
        #expect(sleeping.systemAsleep == true)
        #expect(sleeping.lockSurfaceMayShow == false)
        #expect(sleeping.ownerPresent == false)

        var open = SessionPresence(displaysAwake: true)
        #expect(open.reduce(.sessionRead(unlocked())) == [])
    }

    @Test func anUnreadableSessionIsNeitherShowableNorPresent() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked()))
        #expect(presence.lockSurfaceMayShow == true)
        let lost = presence.reduce(.sessionRead(nil))
        #expect(presence.reading == .unknown)
        #expect(presence.onConsole == false)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.ownerPresent == false)
        #expect(lost == [])

        var hinted = SessionPresence(displaysAwake: true)
        _ = hinted.reduce(.lockNotified)
        let retry = hinted.reduce(.sessionRead(nil))
        #expect(hinted.reading == .unknown)
        #expect(hinted.hint == .locked)
        #expect(hinted.lockSurfaceMayShow == false)
        #expect(hinted.ownerPresent == false)
        #expect(retry == [.readSession(after: 0.5)])
        #expect(hinted.settleLeft == 2)
    }

    @Test func resigningTheConsoleHidesBeforeAnyRead() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked()))
        #expect(presence.lockSurfaceMayShow == true)
        #expect(presence.ownerPresent == false)
        let effects = presence.reduce(.sessionResigned)
        #expect(effects == [.readSession(after: 0)])
        #expect(presence.onConsole == false)
        #expect(presence.reading == .locked)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.ownerPresent == false)
    }

    @Test func sleepAndWakeDoNotRewriteTheReading() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(unlocked()))
        #expect(presence.ownerPresent == true)
        #expect(presence.reduce(.willSleep) == [.readSession(after: 0)])
        #expect(presence.systemAsleep == true)
        #expect(presence.reading == .unlocked)
        #expect(presence.ownerPresent == false)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.reduce(.didWake) == [.readSession(after: 0)])
        #expect(presence.systemAsleep == false)
        #expect(presence.reading == .unlocked)
        #expect(presence.ownerPresent == true)

        var lockedPresence = SessionPresence(displaysAwake: true)
        _ = lockedPresence.reduce(.sessionRead(locked()))
        _ = lockedPresence.reduce(.willSleep)
        #expect(lockedPresence.lockSurfaceMayShow == false)
        #expect(lockedPresence.ownerPresent == false)
        _ = lockedPresence.reduce(.didWake)
        #expect(lockedPresence.reading == .locked)
        #expect(lockedPresence.systemAsleep == false)
        #expect(lockedPresence.ownerPresent == false)
        #expect(lockedPresence.lockSurfaceMayShow == true)
    }

    @Test func aScreensaverHidesTheSurfaceUntilItStops() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked()))
        #expect(presence.lockSurfaceMayShow == true)
        #expect(presence.reduce(.screensaverStarted) == [.readSession(after: 0)])
        #expect(presence.screensaver == true)
        #expect(presence.reading == .locked)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.reduce(.screensaverStopped) == [.readSession(after: 0)])
        #expect(presence.screensaver == false)
        #expect(presence.lockSurfaceMayShow == true)
    }

    @Test func anUnlockedReadClearsTheScreensaver() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked()))
        _ = presence.reduce(.screensaverStarted)
        #expect(presence.screensaver == true)
        let effects = presence.reduce(.sessionRead(unlocked()))
        #expect(presence.screensaver == false)
        #expect(presence.reading == .unlocked)
        #expect(presence.hint == .none)
        #expect(presence.ownerPresent == true)
        #expect(effects == [])
    }

    @Test func aRefreshAsksForAReadAndRefillsTheSettleRun() {
        var presence = SessionPresence(displaysAwake: true)
        let effects = presence.reduce(.refreshRequested)
        #expect(effects == [.readSession(after: 0)])
        #expect(presence.settleLeft == SessionPresence.settleDelays.count)
        #expect(presence.reading == .unknown)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.ownerPresent == false)
    }

    @Test func aDisplaySleepHidesTheSurfaceWithoutChangingTheReading() {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked()))
        #expect(presence.lockSurfaceMayShow == true)
        #expect(presence.reduce(.displaysSlept) == [.readSession(after: 0)])
        #expect(presence.displaysAwake == false)
        #expect(presence.reading == .locked)
        #expect(presence.lockSurfaceMayShow == false)
        #expect(presence.ownerPresent == false)
    }

    @Test(arguments: [
        SessionPresence.Event.lockNotified,
        .unlockNotified,
        .sessionBecameActive,
        .sessionResigned,
        .displaysSlept,
        .displaysWoke,
        .screensaverStarted,
        .screensaverStopped,
        .willSleep,
        .didWake,
        .refreshRequested,
    ])
    func aNoticeDoesNotChangeTheReading(_ event: SessionPresence.Event) {
        var presence = SessionPresence(displaysAwake: true)
        _ = presence.reduce(.sessionRead(locked()))
        let reading = presence.reading
        _ = presence.reduce(event)
        #expect(presence.reading == reading)
    }
}
