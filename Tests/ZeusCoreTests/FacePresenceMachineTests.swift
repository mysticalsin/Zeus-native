import Foundation
import Testing
@testable import ZeusCore

/// One test per row of the state table in docs/FACE-PRESENCE-PLAN.md, plus the safety guards the plan names.
@Suite("Face presence machine")
struct FacePresenceMachineTests {
    typealias Machine = FacePresenceMachine

    // MARK: Builders. Every state is reached through events, never by assigning it.

    static func switchOn(_ camera: Machine.CameraAccess = .authorized, faces: Int = 1, canLock: Bool = true,
                         vaultReadable: Bool = true, at uptime: Double = 100) -> Machine.Event {
        .switchOn(camera: camera, enabledFaces: faces, canLock: canLock, vaultReadable: vaultReadable, uptime: uptime)
    }

    /// Switched on with one face at uptime 100: watching since 100.
    static func watching(faces: Int = 1) -> Machine {
        var machine = Machine()
        _ = machine.handle(switchOn(faces: faces))
        return machine
    }

    /// Present, last seen at 101.
    static func present() -> Machine {
        var machine = watching()
        _ = machine.handle(.observed(.owner, uptime: 101))
        return machine
    }

    /// Away since 100 (watching began at 100, and the first frame showed nobody).
    static func away() -> Machine {
        var machine = watching()
        _ = machine.handle(.observed(.notOwner, uptime: 101))
        return machine
    }

    /// Enrolling with token 1.
    static func enrolling() -> Machine {
        var machine = Machine()
        _ = machine.handle(switchOn(faces: 0))
        return machine
    }

    static func locked(by reason: Machine.PauseReason) -> Machine {
        var machine = watching()
        switch reason {
        case .launch: _ = machine.handle(.launch(storedOn: true))
        case .screenLocked: _ = machine.handle(.screenLocked)
        case .asleep: _ = machine.handle(.willSleep)
        case .lockedByZeus:
            _ = machine.handle(.observed(.notOwner, uptime: 101))
            _ = machine.handle(.tick(uptime: 100 + Machine.defaultLockAfter))
        case .noFace: _ = machine.handle(.facesChanged(enabledFaces: 0, uptime: 102))
        case .zeusCapture: _ = machine.handle(.zeusCapture(active: true, uptime: 102))
        }
        return machine
    }

    /// Every state a machine can be in, each with a label for failure messages.
    static func everyState() -> [(String, Machine)] {
        var consent = Machine()
        _ = consent.handle(switchOn(.notDetermined))
        var unavailable = Machine()
        _ = unavailable.handle(switchOn(canLock: false))
        var off = Machine()
        _ = off.handle(.launch(storedOn: false))
        var states: [(String, Machine)] = [
            ("off", off), ("needsCameraConsent", consent), ("enrolling", enrolling()), ("watching", watching()),
            ("present", present()), ("away", away()), ("unavailable", unavailable),
        ]
        for reason in [Machine.PauseReason.launch, .screenLocked, .asleep, .lockedByZeus, .noFace, .zeusCapture] {
            states.append(("paused \(reason)", locked(by: reason)))
        }
        return states
    }

    static let onStates: [(String, Machine)] = [("watching", watching()), ("present", present()), ("away", away())]

    // MARK: Launch

    @Test func launchWithTheSwitchOnKeepsTheCameraOff() {
        for (label, start) in Self.everyState() where label != "enrolling" {
            var machine = start
            let effects = machine.handle(.launch(storedOn: true))
            #expect(machine.state == .paused(.launch), "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
            #expect(!machine.wantsCamera, "from \(label)")
            #expect(!machine.wantsTicks, "from \(label)")
        }
        var fresh = Machine()
        let effects = fresh.handle(.launch(storedOn: true))
        #expect(fresh.state == .paused(.launch))
        #expect(effects.isEmpty)
        #expect(fresh.switchOn)
    }

    @Test func launchWithTheSwitchOffIsOff() {
        for (label, start) in Self.everyState() where label != "enrolling" {
            var machine = start
            let effects = machine.handle(.launch(storedOn: false))
            #expect(machine.state == .off, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
            #expect(!machine.switchOn)
        }
    }

    // MARK: Switching on

    @Test func switchOnWithoutTheLockCallIsUnavailable() {
        var machine = Machine()
        let effects = machine.handle(Self.switchOn(canLock: false))
        #expect(machine.state == .unavailable(.lock))
        #expect(effects.isEmpty)
        #expect(!machine.wantsCamera)
    }

    @Test func switchOnWithAnUnreadableVaultIsUnavailable() {
        var machine = Machine()
        let effects = machine.handle(Self.switchOn(vaultReadable: false))
        #expect(machine.state == .unavailable(.vault))
        #expect(effects.isEmpty)
        #expect(!machine.wantsCamera)
    }

    @Test func switchOnAsksForConsentWhenTheCameraIsNotDetermined() {
        var machine = Machine()
        let effects = machine.handle(Self.switchOn(.notDetermined))
        #expect(machine.state == .needsCameraConsent)
        #expect(effects == [.askCameraConsent])
        #expect(!machine.wantsCamera)
    }

    @Test func switchOnOpensCameraSettingsWhenTheCameraIsDenied() {
        var machine = Machine()
        let effects = machine.handle(Self.switchOn(.denied))
        #expect(machine.state == .needsCameraConsent)
        #expect(effects == [.openCameraSettings])
        #expect(!machine.wantsCamera)
    }

    @Test func theFirstEnableWithNoFaceWaitsForASecondConfirm() {
        var machine = Machine()
        let first = machine.handle(Self.switchOn(faces: 0))
        #expect(!first.contains { if case .beginEnrollment = $0 { return true } else { return false } })
        #expect(machine.wantsCamera == false)
        let second = machine.handle(.enroll)
        #expect(second.contains { if case .beginEnrollment = $0 { return true } else { return false } })
        #expect(machine.wantsCamera)
    }

    @Test func switchOnWithNoFacesStartsEnrolling() {
        var machine = Machine()
        let effects = machine.handle(Self.switchOn(faces: 0))
        #expect(machine.state == .enrolling(token: 1))
        #expect(effects == [.beginEnrollment(token: 1)])
        #expect(machine.wantsCamera)
        #expect(!machine.wantsTicks)
    }

    @Test func switchOnWithFacesStartsWatching() {
        var machine = Machine()
        let effects = machine.handle(Self.switchOn(faces: 2, at: 250))
        #expect(machine.state == .watching(since: 250))
        #expect(effects.isEmpty)
        #expect(machine.wantsCamera)
        #expect(machine.wantsTicks)
    }

    @Test func consentGrantedContinuesLikeSwitchOn() {
        var withFaces = Machine()
        _ = withFaces.handle(Self.switchOn(.notDetermined))
        let first = withFaces.handle(.consentAnswered(granted: true, enabledFaces: 1, uptime: 140))
        #expect(withFaces.state == .watching(since: 140))
        #expect(first.isEmpty)

        var none = Machine()
        _ = none.handle(Self.switchOn(.denied, faces: 0))
        let second = none.handle(.consentAnswered(granted: true, enabledFaces: 0, uptime: 140))
        #expect(none.state == .enrolling(token: 1))
        #expect(second == [.beginEnrollment(token: 1)])
    }

    @Test func consentRefusedStaysWaitingAndDoesNothing() {
        var machine = Machine()
        _ = machine.handle(Self.switchOn(.notDetermined))
        let effects = machine.handle(.consentAnswered(granted: false, enabledFaces: 1, uptime: 140))
        #expect(machine.state == .needsCameraConsent)
        #expect(effects.isEmpty)
        #expect(!machine.wantsCamera)
    }

    @Test func aConsentAnswerOutsideTheWaitIsIgnored() {
        for (label, start) in Self.everyState() where label != "needsCameraConsent" {
            var machine = start
            let before = machine.state
            let effects = machine.handle(.consentAnswered(granted: true, enabledFaces: 1, uptime: 500))
            #expect(machine.state == before, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
        }
    }

    @Test func switchOnWhileAlreadyOnChangesNothing() {
        for (label, start) in Self.everyState() where !["off", "unavailable"].contains(label) {
            var machine = start
            let before = machine.state
            let effects = machine.handle(Self.switchOn(at: 900))
            #expect(machine.state == before, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
        }
    }

    @Test func switchOnAfterAnUnavailableStateTriesAgain() {
        var machine = Machine()
        _ = machine.handle(Self.switchOn(canLock: false))
        #expect(machine.state == .unavailable(.lock))
        _ = machine.handle(.switchOff)
        #expect(machine.state == .off)
        _ = machine.handle(Self.switchOn(at: 300))
        #expect(machine.state == .watching(since: 300))
        // A retry without the switch cycle works too.
        var direct = Machine()
        _ = direct.handle(Self.switchOn(vaultReadable: false))
        _ = direct.handle(Self.switchOn(at: 310))
        #expect(direct.state == .watching(since: 310))
    }

    // MARK: Switching off

    @Test func switchingOffStopsTheCameraFromEveryState() {
        for (label, start) in Self.everyState() where label != "off" {
            var machine = start
            let wasEnrolling: Machine.Effect? = {
                if case .enrolling(let token) = start.state { return .cancelEnrollment(token: token) }
                return nil
            }()
            let effects = machine.handle(.switchOff)
            #expect(machine.state == .off, "from \(label)")
            #expect(!machine.wantsCamera, "from \(label)")
            #expect(!machine.wantsTicks, "from \(label)")
            #expect(!machine.switchOn, "from \(label)")
            #expect(effects == (wasEnrolling.map { [$0] } ?? []), "from \(label)")
            #expect(machine.presence == .unknown, "from \(label)")
        }
    }

    @Test func offIgnoresEverythingExceptSwitchOnLaunchAndTheSettings() {
        var machine = Machine()
        let events: [Machine.Event] = [
            .enroll, .consentAnswered(granted: true, enabledFaces: 1, uptime: 1), .enrollmentEnded(token: 1, saved: true, enabledFaces: 1, uptime: 1),
            .cameraFailed, .cameraReturned(uptime: 1), .observed(.owner, uptime: 1), .tick(uptime: 1000),
            .screenLocked, .screenUnlocked(uptime: 2, session: .unlocked), .willSleep, .didWake(uptime: 2, session: .unlocked),
            .zeusCapture(active: false, uptime: 2), .lockFinished(ok: false), .switchOff,
        ]
        for event in events {
            let effects = machine.handle(event)
            #expect(machine.state == .off, "\(event)")
            #expect(effects.isEmpty, "\(event)")
        }
    }

    // MARK: Enrolling

    @Test func enrollStartsFromWatchingPresentAndAway() {
        for (label, start) in Self.onStates {
            var machine = start
            let effects = machine.handle(.enroll)
            #expect(machine.state == .enrolling(token: 1), "from \(label)")
            #expect(effects == [.beginEnrollment(token: 1)], "from \(label)")
            #expect(machine.wantsCamera)
            #expect(!machine.wantsTicks)
        }
    }

    @Test func enrollIsIgnoredEverywhereElse() {
        for (label, start) in Self.everyState() where !["watching", "present", "away"].contains(label) {
            var machine = start
            let before = machine.state
            let effects = machine.handle(.enroll)
            #expect(machine.state == before, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
        }
    }

    @Test func eachEnrollmentGetsANewToken() {
        var machine = Self.watching()
        _ = machine.handle(.enroll)
        #expect(machine.state == .enrolling(token: 1))
        _ = machine.handle(.enrollmentEnded(token: 1, saved: false, enabledFaces: 1, uptime: 110))
        let effects = machine.handle(.enroll)
        #expect(machine.state == .enrolling(token: 2))
        #expect(effects == [.beginEnrollment(token: 2)])
    }

    @Test func anEnrollmentThatEndsWithFacesStartsWatching() {
        var machine = Self.enrolling()
        let effects = machine.handle(.enrollmentEnded(token: 1, saved: true, enabledFaces: 1, uptime: 140))
        #expect(machine.state == .watching(since: 140))
        #expect(effects.isEmpty)
    }

    @Test func anEnrollmentThatEndsWithNoFacesPausesWithNoFace() {
        var machine = Self.enrolling()
        let effects = machine.handle(.enrollmentEnded(token: 1, saved: false, enabledFaces: 0, uptime: 140))
        #expect(machine.state == .paused(.noFace))
        #expect(effects.isEmpty)
        #expect(!machine.wantsCamera)
    }

    @Test func aStaleEnrollmentEndIsIgnored() {
        var machine = Self.enrolling()
        let stale = machine.handle(.enrollmentEnded(token: 7, saved: true, enabledFaces: 3, uptime: 140))
        #expect(machine.state == .enrolling(token: 1))
        #expect(stale.isEmpty)
        // And one that arrives after the enrollment was cancelled by a lock changes nothing.
        var cancelled = Self.enrolling()
        _ = cancelled.handle(.screenLocked)
        let late = cancelled.handle(.enrollmentEnded(token: 1, saved: true, enabledFaces: 1, uptime: 140))
        #expect(cancelled.state == .paused(.screenLocked))
        #expect(late.isEmpty)
        // And one that arrives while watching.
        var watching = Self.watching()
        let whileWatching = watching.handle(.enrollmentEnded(token: 1, saved: true, enabledFaces: 1, uptime: 140))
        #expect(watching.state == .watching(since: 100))
        #expect(whileWatching.isEmpty)
    }

    @Test func framesDuringEnrollmentDoNotMoveTheMachine() {
        var machine = Self.enrolling()
        let first = machine.handle(.observed(.owner, uptime: 105))
        let second = machine.handle(.tick(uptime: 5000))
        #expect(machine.state == .enrolling(token: 1))
        #expect(first.isEmpty && second.isEmpty)
    }

    // MARK: Enabled faces changing

    @Test func removingEveryFaceFromAnOnStatePausesWithNoFace() {
        for (label, start) in Self.onStates {
            var machine = start
            let effects = machine.handle(.facesChanged(enabledFaces: 0, uptime: 200))
            #expect(machine.state == .paused(.noFace), "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
            #expect(!machine.wantsCamera, "from \(label)")
        }
    }

    @Test func gettingAFaceBackFromNoFaceStartsWatching() {
        var machine = Self.locked(by: .noFace)
        let effects = machine.handle(.facesChanged(enabledFaces: 1, uptime: 300))
        #expect(machine.state == .watching(since: 300))
        #expect(effects.isEmpty)
    }

    @Test func aFaceCountChangeThatKeepsFacesChangesNothing() {
        for (label, start) in Self.onStates {
            var machine = start
            let before = machine.state
            _ = machine.handle(.facesChanged(enabledFaces: 2, uptime: 200))
            #expect(machine.state == before, "from \(label)")
        }
    }

    @Test func theFaceCountIsRememberedForTheNextStart() {
        // Launch with the switch on, then the faces arrive, then an unlock: watching, or no face when there are none.
        var withFace = Machine()
        _ = withFace.handle(.launch(storedOn: true))
        _ = withFace.handle(.facesChanged(enabledFaces: 1, uptime: 10))
        #expect(withFace.state == .paused(.launch))
        _ = withFace.handle(.screenUnlocked(uptime: 20, session: .unlocked))
        #expect(withFace.state == .watching(since: 20))

        var without = Machine()
        _ = without.handle(.launch(storedOn: true))
        _ = without.handle(.facesChanged(enabledFaces: 0, uptime: 10))
        _ = without.handle(.screenUnlocked(uptime: 20, session: .unlocked))
        #expect(without.state == .paused(.noFace))
        #expect(!without.wantsCamera)
    }

    // MARK: Frames

    @Test func watchingSeesTheOwnerAndBecomesPresent() {
        var machine = Self.watching()
        let effects = machine.handle(.observed(.owner, uptime: 103))
        #expect(machine.state == .present(lastSeen: 103))
        #expect(effects.isEmpty)
        #expect(machine.presence == .present)
    }

    @Test func watchingWithNobodyIsAwayFromTheStartOfWatching() {
        var machine = Self.watching()
        let effects = machine.handle(.observed(.notOwner, uptime: 104))
        #expect(machine.state == .away(since: 100))
        #expect(effects.isEmpty)
        #expect(machine.presence == .absent)
    }

    @Test func presentKeepsRefreshingWhileTheOwnerIsSeen() {
        var machine = Self.present()
        _ = machine.handle(.observed(.owner, uptime: 102))
        _ = machine.handle(.observed(.owner, uptime: 110))
        #expect(machine.state == .present(lastSeen: 110))
    }

    @Test func aMissShorterThanTheGraceKeepsPresent() {
        var machine = Self.present()
        #expect(Machine.absentGrace == 3)
        let miss = machine.handle(.observed(.notOwner, uptime: 102.9))
        #expect(machine.state == .present(lastSeen: 101))
        #expect(miss.isEmpty)
        let tick = machine.handle(.tick(uptime: 103.9))
        #expect(machine.state == .present(lastSeen: 101))
        #expect(tick.isEmpty)
        #expect(machine.presence == .present)
        // The owner coming back inside the grace resets it.
        _ = machine.handle(.observed(.owner, uptime: 103.5))
        #expect(machine.state == .present(lastSeen: 103.5))
    }

    @Test func aMissAsLongAsTheGraceTurnsPresentIntoAway() {
        var byFrame = Self.present()
        let first = byFrame.handle(.observed(.notOwner, uptime: 104))
        #expect(byFrame.state == .away(since: 101))
        #expect(first.isEmpty)

        var byTick = Self.present()
        let second = byTick.handle(.tick(uptime: 104))
        #expect(byTick.state == .away(since: 101))
        #expect(second.isEmpty)
        #expect(byTick.presence == .absent)
    }

    @Test func theOwnerReturningFromAwayIsPresent() {
        var machine = Self.away()
        let effects = machine.handle(.observed(.owner, uptime: 150))
        #expect(machine.state == .present(lastSeen: 150))
        #expect(effects.isEmpty)
    }

    @Test func aFrameInAnyStateWithoutTheCameraIsDropped() {
        for (label, start) in Self.everyState() where !["watching", "present", "away"].contains(label) {
            var machine = start
            let before = machine.state
            let effects = machine.handle(.observed(.owner, uptime: 600))
            #expect(machine.state == before, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
        }
    }

    @Test func aTimeThatIsNotANumberIsIgnored() {
        var machine = Self.present()
        for event: Machine.Event in [.observed(.notOwner, uptime: .nan), .tick(uptime: .infinity), .observed(.owner, uptime: -.infinity)] {
            let effects = machine.handle(event)
            #expect(machine.state == .present(lastSeen: 101), "\(event)")
            #expect(effects.isEmpty)
        }
    }

    @Test func aCameraThatSendsNoFramesGoesUnavailable() {
        #expect(Machine.stallLimit == 10)
        var machine = Self.watching()
        let early = machine.handle(.tick(uptime: 109.9))
        #expect(machine.state == .watching(since: 100))
        #expect(early.isEmpty)
        let due = machine.handle(.tick(uptime: 110))
        #expect(machine.state == .unavailable(.camera))
        #expect(due.isEmpty)
        #expect(!machine.wantsCamera)
        // A frame before the limit keeps it alive.
        var fed = Self.watching()
        _ = fed.handle(.observed(.owner, uptime: 105))
        _ = fed.handle(.tick(uptime: 200.5))
        #expect(fed.state != .unavailable(.camera))
    }

    // MARK: The lock

    @Test func awayLocksExactlyOnceWhenTheTimeRunsOut() {
        var machine = Self.away()
        #expect(machine.lockAfter == 120)
        let early = machine.handle(.tick(uptime: 219.9))
        #expect(machine.state == .away(since: 100))
        #expect(early.isEmpty)
        let due = machine.handle(.tick(uptime: 220))
        #expect(machine.state == .paused(.lockedByZeus))
        #expect(due == [.lockNow])
        #expect(!machine.wantsCamera)
        #expect(!machine.wantsTicks)
        // Nothing more can ask for the lock again.
        var count = 1
        for step in 1...20 {
            let effects = machine.handle(.tick(uptime: 220 + Double(step)))
            count += effects.filter { $0 == .lockNow }.count
            let observed = machine.handle(.observed(.notOwner, uptime: 220 + Double(step)))
            count += observed.filter { $0 == .lockNow }.count
        }
        #expect(count == 1)
        #expect(machine.state == .paused(.lockedByZeus))
    }

    @Test func aFrameAtTheDeadlineAlsoLocks() {
        var machine = Self.away()
        let effects = machine.handle(.observed(.notOwner, uptime: 220))
        #expect(machine.state == .paused(.lockedByZeus))
        #expect(effects == [.lockNow])
    }

    @Test func theTimeCountsFromTheLastSightingOfTheOwner() {
        var machine = Self.present()
        _ = machine.handle(.observed(.owner, uptime: 130))
        _ = machine.handle(.tick(uptime: 133))
        #expect(machine.state == .away(since: 130))
        let early = machine.handle(.tick(uptime: 249))
        #expect(early.isEmpty)
        let due = machine.handle(.tick(uptime: 250))
        #expect(due == [.lockNow])
    }

    @Test func aLongGapLocksAtOnceWhenTheFrameArrives() {
        // A Mac that stalled for ten minutes: the first frame after it sees nobody and the limit has passed.
        var machine = Self.present()
        let effects = machine.handle(.observed(.notOwner, uptime: 800))
        #expect(machine.state == .paused(.lockedByZeus))
        #expect(effects == [.lockNow])
    }

    @Test func everyLockAfterChoiceLocksAtItsOwnTime() {
        for seconds in [30.0, 60, 120, 300, 600] {
            var machine = Self.away()
            _ = machine.handle(.setLockAfter(seconds: seconds))
            #expect(machine.lockAfter == seconds)
            let early = machine.handle(.tick(uptime: 100 + seconds - 0.1))
            #expect(early.isEmpty, "\(seconds)")
            let due = machine.handle(.tick(uptime: 100 + seconds))
            #expect(due == [.lockNow], "\(seconds)")
        }
    }

    @Test func aChangedLimitIsReadOnTheNextTickWithoutRestartingTheCountdown() {
        var machine = Self.away()
        _ = machine.handle(.setLockAfter(seconds: 600))
        #expect(machine.state == .away(since: 100))
        let none = machine.handle(.tick(uptime: 220))
        #expect(none.isEmpty)
        _ = machine.handle(.setLockAfter(seconds: 30))
        #expect(machine.state == .away(since: 100))
        let due = machine.handle(.tick(uptime: 221))
        #expect(due == [.lockNow])
    }

    @Test func aLimitThatIsNotAChoiceFallsBackToTwoMinutes() {
        var machine = Machine()
        _ = machine.handle(.setLockAfter(seconds: 45))
        #expect(machine.lockAfter == 120)
        _ = machine.handle(.setLockAfter(seconds: .nan))
        #expect(machine.lockAfter == 120)
        _ = machine.handle(.setLockAfter(seconds: 300))
        #expect(machine.lockAfter == 300)
        _ = machine.handle(.setLockAfter(seconds: -1))
        #expect(machine.lockAfter == 120)
    }

    @Test func aFailedLockGoesUnavailableAndNeverRetries() {
        var machine = Self.locked(by: .lockedByZeus)
        let failed = machine.handle(.lockFinished(ok: false))
        #expect(machine.state == .unavailable(.lock))
        #expect(failed.isEmpty)
        var asked = 0
        for step in 1...30 {
            asked += machine.handle(.tick(uptime: 400 + Double(step))).filter { $0 == .lockNow }.count
            asked += machine.handle(.observed(.notOwner, uptime: 400 + Double(step))).filter { $0 == .lockNow }.count
        }
        #expect(asked == 0)
        #expect(machine.state == .unavailable(.lock))
    }

    @Test func aLockThatWorkedChangesNothing() {
        var machine = Self.locked(by: .lockedByZeus)
        let effects = machine.handle(.lockFinished(ok: true))
        #expect(machine.state == .paused(.lockedByZeus))
        #expect(effects.isEmpty)
    }

    @Test func aLockResultOutsideTheLockedStateIsIgnored() {
        for (label, start) in Self.everyState() where label != "paused lockedByZeus" {
            var machine = start
            let before = machine.state
            let effects = machine.handle(.lockFinished(ok: false))
            #expect(machine.state == before, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
        }
    }

    // MARK: Screen lock and sleep

    @Test func lockingTheScreenStopsTheCameraFromEveryOnState() {
        for (label, start) in Self.onStates {
            var machine = start
            let effects = machine.handle(.screenLocked)
            #expect(machine.state == .paused(.screenLocked), "from \(label)")
            #expect(!machine.wantsCamera, "from \(label)")
            #expect(!machine.wantsTicks, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
        }
        var enrolling = Self.enrolling()
        let cancel = enrolling.handle(.screenLocked)
        #expect(enrolling.state == .paused(.screenLocked))
        #expect(cancel == [.cancelEnrollment(token: 1)])
        #expect(!enrolling.wantsCamera)
    }

    @Test func aLockAfterTheMachineLockedKeepsTheReason() {
        var machine = Self.locked(by: .lockedByZeus)
        let effects = machine.handle(.screenLocked)
        #expect(machine.state == .paused(.lockedByZeus))
        #expect(effects.isEmpty)
    }

    @Test func otherPausesBecomeScreenLockedWhenTheScreenLocks() {
        for reason in [Machine.PauseReason.launch, .asleep, .noFace, .zeusCapture] {
            var machine = Self.locked(by: reason)
            _ = machine.handle(.screenLocked)
            #expect(machine.state == .paused(.screenLocked), "\(reason)")
        }
    }

    @Test func sleepStopsTheCameraAndWakeWhileLockedKeepsItOff() {
        for (label, start) in Self.onStates {
            var machine = start
            let effects = machine.handle(.willSleep)
            #expect(machine.state == .paused(.asleep), "from \(label)")
            #expect(!machine.wantsCamera, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
            // Waking into a locked or unknown session starts nothing.
            for session in [Machine.SessionLockState.locked, .unknown] {
                var woken = machine
                let wake = woken.handle(.didWake(uptime: 500, session: session))
                #expect(woken.state == .paused(.asleep), "\(label) \(session)")
                #expect(wake.isEmpty)
                #expect(!woken.wantsCamera)
            }
            // Waking into an unlocked session resumes watching.
            var open = machine
            _ = open.handle(.didWake(uptime: 500, session: .unlocked))
            #expect(open.state == .watching(since: 500), "from \(label)")
        }
        var enrolling = Self.enrolling()
        let cancel = enrolling.handle(.willSleep)
        #expect(enrolling.state == .paused(.asleep))
        #expect(cancel == [.cancelEnrollment(token: 1)])
    }

    @Test func lockingDuringEnrollmentSavesNothing() {
        for event: Machine.Event in [.screenLocked, .willSleep] {
            var machine = Self.enrolling()
            let effects = machine.handle(event)
            // The enrollment is cancelled, and a result that still arrives is stale.
            #expect(effects == [.cancelEnrollment(token: 1)], "\(event)")
            let late = machine.handle(.enrollmentEnded(token: 1, saved: true, enabledFaces: 1, uptime: 130))
            #expect(late.isEmpty)
            #expect(!machine.wantsCamera)
            if case .watching = machine.state { Issue.record("watching after \(event)") }
        }
        var capture = Self.enrolling()
        let cancelled = capture.handle(.zeusCapture(active: true, uptime: 120))
        #expect(cancelled == [.cancelEnrollment(token: 1)])
        #expect(capture.state == .paused(.zeusCapture))
        var failed = Self.enrolling()
        let failedEffects = failed.handle(.cameraFailed)
        #expect(failedEffects == [.cancelEnrollment(token: 1)])
    }

    @Test func aSessionThatIsNotPlainlyUnlockedStartsNothingOnUnlock() {
        for reason in [Machine.PauseReason.launch, .screenLocked, .asleep, .lockedByZeus] {
            for session in [Machine.SessionLockState.locked, .unknown] {
                var machine = Self.locked(by: reason)
                let unlock = machine.handle(.screenUnlocked(uptime: 700, session: session))
                #expect(machine.state == .paused(reason), "\(reason) \(session)")
                #expect(unlock.isEmpty)
                let wake = machine.handle(.didWake(uptime: 701, session: session))
                #expect(machine.state == .paused(reason), "\(reason) \(session)")
                #expect(wake.isEmpty)
            }
        }
    }

    @Test func anUnknownSessionStateOnUnlockStartsNothing() {
        var machine = Machine()
        _ = machine.handle(.launch(storedOn: true))
        _ = machine.handle(.facesChanged(enabledFaces: 1, uptime: 1))
        let unlock = machine.handle(.screenUnlocked(uptime: 5, session: .unknown))
        #expect(machine.state == .paused(.launch))
        #expect(unlock.isEmpty)
        #expect(!machine.wantsCamera)
    }

    @Test func anUnlockedSessionResumesFromEachLockPause() {
        for reason in [Machine.PauseReason.launch, .screenLocked, .asleep, .lockedByZeus] {
            var byUnlock = Self.locked(by: reason)
            let first = byUnlock.handle(.screenUnlocked(uptime: 800, session: .unlocked))
            #expect(byUnlock.state == .watching(since: 800), "\(reason)")
            #expect(first.isEmpty)
            var byWake = Self.locked(by: reason)
            let second = byWake.handle(.didWake(uptime: 801, session: .unlocked))
            #expect(byWake.state == .watching(since: 801), "\(reason)")
            #expect(second.isEmpty)
        }
    }

    @Test func anUnlockWithNoFaceGoesToNoFace() {
        var machine = Self.locked(by: .screenLocked)
        _ = machine.handle(.facesChanged(enabledFaces: 0, uptime: 701))
        #expect(machine.state == .paused(.screenLocked))
        _ = machine.handle(.screenUnlocked(uptime: 702, session: .unlocked))
        #expect(machine.state == .paused(.noFace))
    }

    @Test func anUnlockWhileWatchingChangesNothing() {
        for (label, start) in Self.onStates {
            var machine = start
            let before = machine.state
            _ = machine.handle(.screenUnlocked(uptime: 900, session: .unlocked))
            _ = machine.handle(.didWake(uptime: 901, session: .unlocked))
            #expect(machine.state == before, "from \(label)")
        }
        for reason in [Machine.PauseReason.noFace, .zeusCapture] {
            var machine = Self.locked(by: reason)
            _ = machine.handle(.screenUnlocked(uptime: 900, session: .unlocked))
            #expect(machine.state == .paused(reason), "\(reason)")
        }
    }

    // MARK: Zeus capture (the teleprompter)

    @Test func aTeleprompterRecordingPausesAndResumes() {
        for (label, start) in Self.onStates {
            var machine = start
            let effects = machine.handle(.zeusCapture(active: true, uptime: 300))
            #expect(machine.state == .paused(.zeusCapture), "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
            #expect(!machine.wantsCamera, "from \(label)")
            let back = machine.handle(.zeusCapture(active: false, uptime: 340))
            #expect(machine.state == .watching(since: 340), "from \(label)")
            #expect(back.isEmpty)
        }
    }

    @Test func aRecordingThatOutlastsALockStillHoldsTheCameraOff() {
        var machine = Self.watching()
        _ = machine.handle(.zeusCapture(active: true, uptime: 300))
        _ = machine.handle(.screenLocked)
        #expect(machine.state == .paused(.screenLocked))
        _ = machine.handle(.screenUnlocked(uptime: 400, session: .unlocked))
        #expect(machine.state == .paused(.zeusCapture))
        #expect(!machine.wantsCamera)
        _ = machine.handle(.zeusCapture(active: false, uptime: 410))
        #expect(machine.state == .watching(since: 410))
    }

    @Test func switchingOnDuringARecordingWaitsForTheRecording() {
        var machine = Machine()
        _ = machine.handle(.zeusCapture(active: true, uptime: 90))
        #expect(machine.state == .off)
        let effects = machine.handle(Self.switchOn(at: 100))
        #expect(machine.state == .paused(.zeusCapture))
        #expect(effects.isEmpty)
        _ = machine.handle(.zeusCapture(active: false, uptime: 130))
        #expect(machine.state == .watching(since: 130))
    }

    @Test func theEndOfARecordingElsewhereChangesNothing() {
        for (label, start) in Self.everyState() where label != "paused zeusCapture" {
            var machine = start
            let before = machine.state
            let effects = machine.handle(.zeusCapture(active: false, uptime: 900))
            #expect(machine.state == before, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
        }
    }

    // MARK: Camera trouble

    @Test func aCameraFailureStopsEveryCameraState() {
        for (label, start) in Self.onStates {
            var machine = start
            let effects = machine.handle(.cameraFailed)
            #expect(machine.state == .unavailable(.camera), "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
            #expect(!machine.wantsCamera, "from \(label)")
        }
    }

    @Test func aCameraFailureOutsideTheCameraStatesIsIgnored() {
        for (label, start) in Self.everyState() where !["watching", "present", "away", "enrolling"].contains(label) {
            var machine = start
            let before = machine.state
            let effects = machine.handle(.cameraFailed)
            #expect(machine.state == before, "from \(label)")
            #expect(effects.isEmpty, "from \(label)")
        }
    }

    @Test func theCameraReturningOrAnUnlockStartsWatchingAgain() {
        var byCamera = Machine()
        _ = byCamera.handle(Self.switchOn())
        _ = byCamera.handle(.cameraFailed)
        let first = byCamera.handle(.cameraReturned(uptime: 500))
        #expect(byCamera.state == .watching(since: 500))
        #expect(first.isEmpty)

        var byUnlock = Machine()
        _ = byUnlock.handle(Self.switchOn())
        _ = byUnlock.handle(.cameraFailed)
        let locked = byUnlock.handle(.screenUnlocked(uptime: 600, session: .locked))
        #expect(byUnlock.state == .unavailable(.camera))
        #expect(locked.isEmpty)
        _ = byUnlock.handle(.screenUnlocked(uptime: 601, session: .unlocked))
        #expect(byUnlock.state == .watching(since: 601))
    }

    @Test func otherUnavailableReasonsDoNotClearByThemselves() {
        var noLock = Machine()
        _ = noLock.handle(Self.switchOn(canLock: false))
        _ = noLock.handle(.cameraReturned(uptime: 500))
        _ = noLock.handle(.screenUnlocked(uptime: 501, session: .unlocked))
        #expect(noLock.state == .unavailable(.lock))
        var vault = Machine()
        _ = vault.handle(Self.switchOn(vaultReadable: false))
        _ = vault.handle(.cameraReturned(uptime: 500))
        _ = vault.handle(.screenUnlocked(uptime: 501, session: .unlocked))
        #expect(vault.state == .unavailable(.vault))
    }

    // MARK: Derived values

    @Test func wantsCameraIsTrueOnlyInFourStates() {
        for (label, machine) in Self.everyState() {
            let expected = ["enrolling", "watching", "present", "away"].contains(label)
            #expect(machine.wantsCamera == expected, "\(label)")
        }
    }

    @Test func wantsTicksIsTrueOnlyInThreeStates() {
        for (label, machine) in Self.everyState() {
            let expected = ["watching", "present", "away"].contains(label)
            #expect(machine.wantsTicks == expected, "\(label)")
        }
    }

    @Test func canEnrollOnlyWhileWatchingPresentOrAway() {
        for (label, machine) in Self.everyState() {
            let expected = ["watching", "present", "away"].contains(label)
            #expect(machine.canEnroll == expected, "\(label)")
        }
    }

    @Test func presenceIsReadOnlyAndKnownOnlyForPresentAndAway() {
        for (label, machine) in Self.everyState() {
            switch label {
            case "present": #expect(machine.presence == .present)
            case "away": #expect(machine.presence == .absent)
            default: #expect(machine.presence == .unknown, "\(label)")
            }
        }
    }

    @Test func theCountdownRunsOnlyInAwayAndNeverBelowZero() {
        let machine = Self.away()
        #expect(machine.countdown(at: 100) == 120)
        #expect(machine.countdown(at: 160) == 60)
        #expect(machine.countdown(at: 220) == 0)
        #expect(machine.countdown(at: 9999) == 0)
        for (label, other) in Self.everyState() where label != "away" {
            #expect(other.countdown(at: 150) == nil, "\(label)")
        }
    }

    @Test func everyStateHasALogNameWithNoTimeOrToken() {
        var names = Set<String>()
        for (label, machine) in Self.everyState() {
            let name = machine.state.logName
            let hasNumber = name.contains { $0.isNumber }
            #expect(!hasNumber, "\(label): \(name)")
            names.insert(name)
        }
        #expect(names == ["off", "needsCameraConsent", "enrolling", "watching", "present", "away", "unavailable(lock)",
                          "paused(launch)", "paused(screenLocked)", "paused(asleep)", "paused(lockedByZeus)",
                          "paused(noFace)", "paused(zeusCapture)"])
    }

    @Test func theLockChoicesAreTheFiveTheOwnerCanPick() {
        #expect(FaceLockAfter.choices.map(\.label) == ["30 seconds", "1 minute", "2 minutes", "5 minutes", "10 minutes"])
        #expect(FaceLockAfter.choices.map(\.seconds) == [30, 60, 120, 300, 600])
        #expect(FaceLockAfter.defaultLabel == "2 minutes")
        #expect(FaceLockAfter.defaultSeconds == 120)
        #expect(Machine.defaultLockAfter == 120)
        #expect(FaceLockAfter.seconds(forLabel: "5 minutes") == 300)
        #expect(FaceLockAfter.seconds(forLabel: "an hour") == 120)
        #expect(FaceLockAfter.seconds(forLabel: "") == 120)
        #expect(Machine().lockAfter == 120)
    }
}
