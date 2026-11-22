import Foundation
import Testing
@testable import ZeusCore

@Suite("Face verification machine")
struct FaceVerificationMachineTests {
    @Test func defaultsFailClosed() {
        let machine = FaceVerificationMachine()
        #expect(machine.phase == .disabled)
        #expect(!machine.approvalEnabled)
        #expect(!machine.enrolled)
        #expect(!machine.wantsCamera)
        #expect(machine.failures == 0)
        #expect(machine.grant == nil)
        #expect(machine.audit.isEmpty)
        #expect(machine.camera == .notDetermined)
    }

    @Test func cameraConsentIsAskedOnlyWhenTheFeatureIsEnabled() {
        var machine = FaceVerificationMachine()
        let before = machine.handle(.capture(.noFace, uptime: 1))
            + machine.handle(.beginEnrollment)
            + machine.handle(.beginApproval(FaceVerificationFixtures.action("early"), uptime: 1))
        #expect(!before.contains(.askCameraConsent))
        #expect(!before.contains(.startCamera))
        #expect(!machine.wantsCamera)

        let asking = machine.handle(.enable(enrolled: false, camera: .notDetermined, uptime: 2))
        #expect(asking == [.askCameraConsent])
        #expect(machine.phase == .notEnrolled)
        #expect(!machine.wantsCamera)

        let again = machine.handle(.enable(enrolled: false, camera: .notDetermined, uptime: 3))
        #expect(again.isEmpty)
        _ = machine.handle(.cameraAnswered(granted: true))
        #expect(machine.camera == .authorized)
        #expect(!machine.wantsCamera)
        let started = machine.handle(.beginEnrollment)
        #expect(started.contains(.startCamera))
        #expect(machine.wantsCamera)
        #expect(machine.phase == .enrolling)
    }

    @Test func deniedCameraNeverStartsAndOffersTheFallback() {
        var machine = FaceVerificationMachine()
        _ = machine.handle(.enable(enrolled: true, camera: .denied, uptime: 1))
        #expect(machine.phase == .idle)
        #expect(!machine.wantsCamera)
        #expect(machine.lastFailure == .permissionDenied)
        let effects = machine.handle(.beginApproval(FaceVerificationFixtures.action("denied"), uptime: 2))
        #expect(!effects.contains(.startCamera))
        #expect(machine.phase == .rejected || machine.phase == .lockedOut)
        #expect(machine.fallbackOffer?.touch == true)
        #expect(machine.fallbackOffer?.password == true)
        #expect(!machine.wantsCamera)
    }

    @Test func enrollmentRefusesAnImageAndDeleteIsOneAction() {
        var machine = FaceVerificationFixtures.enrolling()
        #expect(machine.wantsCamera)
        let refused = machine.handle(.enrollmentSaved(image: Data([1, 2, 3]), thumbnail: nil))
        #expect(refused.contains(.refuseImage))
        #expect(refused.contains(.stopCamera))
        #expect(!machine.enrolled)
        #expect(machine.phase == .notEnrolled)
        #expect(!machine.wantsCamera)

        var saved = FaceVerificationFixtures.enrolling()
        let stored = saved.handle(.enrollmentSaved(image: nil, thumbnail: nil))
        #expect(stored.contains(.stopCamera))
        #expect(!stored.contains(.refuseImage))
        #expect(saved.enrolled)
        #expect(saved.phase == .idle)

        let deleted = saved.handle(.deleteTemplate)
        #expect(deleted.contains(.templateDeleted))
        #expect(!saved.enrolled)
        #expect(saved.phase == .notEnrolled)
        _ = saved.handle(.beginApproval(FaceVerificationFixtures.action("gone"), uptime: 4))
        #expect(saved.grant == nil)
        #expect(saved.phase != .matched)
    }

    @Test func matchedRequiresLivenessAndBindsTheNonce() {
        var skipped = FaceVerificationFixtures.liveness()
        _ = skipped.handle(.identity(matched: true, uptime: 12))
        #expect(skipped.phase == .livenessCheck)
        #expect(skipped.grant == nil)
        #expect(!skipped.livenessPassed)

        var failedLife = FaceVerificationFixtures.liveness(nonce: "life")
        _ = failedLife.handle(.liveness(FaceLivenessResult(blinked: false, turnedHead: false, virtualCamera: false), uptime: 12))
        #expect(failedLife.phase != .matched)
        #expect(failedLife.grant == nil)

        var virtual = FaceVerificationFixtures.liveness(nonce: "virt")
        _ = virtual.handle(.liveness(FaceLivenessResult(blinked: true, turnedHead: false, virtualCamera: true), uptime: 12))
        #expect(virtual.phase != .matched)

        let action = FaceVerificationFixtures.action("bound-nonce", id: "specific-action")
        var machine = FaceVerificationFixtures.passedLiveness(nonce: action.nonce, id: action.id)
        #expect(machine.livenessPassed)
        _ = machine.handle(.identity(matched: true, uptime: 13))
        #expect(machine.phase == .matched)
        #expect(machine.grant == FaceApprovalGrant(actionID: action.id, nonce: action.nonce, method: .face))
        #expect(machine.issuedNonces.contains(action.nonce))
        #expect(!machine.wantsCamera)
        #expect(machine.audit.last?.result == .allowed)

        _ = machine.handle(.beginApproval(action, uptime: 14))
        #expect(machine.phase == .matched)
        #expect(machine.grant?.nonce == action.nonce)
    }

    @Test func aGrantCannotBeReplayedForAnotherAction() {
        let first = FaceVerificationFixtures.action("nonce-a", id: "action-a")
        let second = FaceVerificationFixtures.action("nonce-b", id: "action-b")
        var machine = FaceVerificationFixtures.matched(nonce: first.nonce, id: first.id)
        let grant = machine.grant
        let firstClear = ApprovalFaceGate.clear(grant: grant, action: first, consumed: [])
        #expect(firstClear.sides.cardCleared && firstClear.sides.terminalCleared)
        let replay = ApprovalFaceGate.clear(grant: grant, action: first, consumed: firstClear.consumed)
        #expect(replay.sides == .neither)
        let swapped = ApprovalFaceGate.clear(grant: grant, action: second, consumed: [])
        #expect(swapped.sides == .neither)

        _ = machine.handle(.beginApproval(second, uptime: 20))
        #expect(machine.phase == .capturing)
        #expect(machine.grant == nil)
        #expect(machine.livenessPassed == false)
        _ = machine.handle(.identity(matched: true, uptime: 21))
        #expect(machine.phase != .matched)
    }

    /// ZB-001. The action that is already open cannot leave `.lockedOut` through a successful fallback.
    @Test func zb001TheOpenActionCannotFallbackOutOfLockout() {
        var machine = FaceVerificationMachine()
        _ = machine.handle(.enable(enrolled: true, camera: .authorized, uptime: 1))
        let limit = FaceVerificationPolicy.failureLimit
        for index in 0..<(limit - 1) {
            let warmup = ApprovalAction(id: "warmup", nonce: "n\(index)")
            _ = machine.handle(.beginApproval(warmup, uptime: 10 + Double(index)))
            _ = machine.handle(.capture(.noFace, uptime: 10 + Double(index)))
        }
        let open = ApprovalAction(id: "pay", nonce: "open-nonce")
        _ = machine.handle(.beginApproval(open, uptime: 100))
        _ = machine.handle(.capture(.noFace, uptime: 100))
        #expect(machine.phase == .lockedOut)
        #expect(machine.grant == nil)
        let failures = machine.failures
        let started = machine.lockoutStarted
        _ = machine.handle(.fallbackResult(succeeded: true, action: open, uptime: 101))
        #expect(machine.phase == .lockedOut)
        #expect(machine.grant == nil)
        #expect(machine.failures == failures)
        #expect(machine.lockoutStarted == started)
    }

    @Test func fallbackApprovesOnlyTheOpenActionAndNotDuringLockout() {
        let action = FaceVerificationFixtures.action("fallback-nonce")
        var machine = FaceVerificationFixtures.fallback(nonce: action.nonce)
        #expect(machine.phase == .fallback)
        #expect(!machine.wantsCamera)
        let wrong = FaceVerificationFixtures.action("other")
        _ = machine.handle(.fallbackResult(succeeded: true, action: wrong, uptime: 15))
        #expect(machine.grant == nil)
        #expect(machine.phase == .fallback)
        _ = machine.handle(.fallbackResult(succeeded: true, action: action, uptime: 16))
        #expect(machine.phase == .idle)
        #expect(machine.grant == FaceApprovalGrant(actionID: action.id, nonce: action.nonce, method: .localAuthentication))
        #expect(machine.phase != .matched)
        #expect(machine.audit.contains { $0.result == .fallback })

        var locked = FaceVerificationFixtures.locked()
        #expect(locked.phase == .lockedOut)
        _ = locked.handle(.chooseFallback)
        #expect(locked.phase == .lockedOut)
        _ = locked.handle(.fallbackResult(succeeded: true, action: FaceVerificationFixtures.action("locked"), uptime: 1_001))
        #expect(locked.grant == nil)
    }

    @Test func lockoutBoundariesUseThePinnedLimitAndDuration() {
        let limit = FaceVerificationPolicy.failureLimit
        let duration = FaceVerificationPolicy.lockoutSeconds
        let started = 5_000.0
        var below = FaceVerificationFixtures.fail(times: limit - 1, at: started)
        #expect(below.failures == limit - 1)
        #expect(below.phase == .rejected)
        _ = below.handle(.beginApproval(FaceVerificationFixtures.action("still-open"), uptime: started))
        #expect(below.phase == .capturing)

        let atLimit = FaceVerificationFixtures.locked(at: started)
        #expect(atLimit.failures == limit)
        #expect(atLimit.phase == .lockedOut)
        #expect(atLimit.lockoutStarted == started)

        var early = atLimit
        _ = early.handle(.tick(uptime: started - 1))
        #expect(early.phase == .lockedOut)

        var exact = atLimit
        _ = exact.handle(.tick(uptime: started + duration))
        #expect(exact.phase == .lockedOut)
        #expect(exact.grant == nil)
        #expect(exact.failures == limit)

        var after = atLimit
        _ = after.handle(.tick(uptime: started + duration + 0.001))
        #expect(after.phase == .idle)
        #expect(after.failures == 0)
        #expect(after.lockoutStarted == nil)
        _ = after.handle(.chooseFallback)
        #expect(after.phase == .idle)
        _ = after.handle(.beginApproval(FaceVerificationFixtures.action("after-lock"), uptime: started + duration + 1))
        #expect(after.phase == .capturing)
        _ = after.handle(.capture(.timeout, uptime: started + duration + 1))
        _ = after.handle(.chooseFallback)
        _ = after.handle(.fallbackResult(succeeded: true, action: FaceVerificationFixtures.action("after-lock"), uptime: started + duration + 2))
        #expect(after.grant?.method == .localAuthentication)
    }

    @Test func aDeniedCameraDuringACheckLocksFromThatCheckClock() {
        let started = 2_000.0
        var machine = FaceVerificationFixtures.fail(times: FaceVerificationPolicy.failureLimit - 1, at: started)
        _ = machine.handle(.beginApproval(FaceVerificationFixtures.action("late-denial"), uptime: started))
        _ = machine.handle(.cameraAnswered(granted: false))
        #expect(machine.phase == .lockedOut)
        #expect(machine.lockoutStarted == started)
        _ = machine.handle(.tick(uptime: started + FaceVerificationPolicy.lockoutSeconds))
        #expect(machine.phase == .lockedOut)
    }

    @Test func disableDoesNotClearAnActiveLockout() {
        var locked = FaceVerificationFixtures.locked(at: 80)
        _ = locked.handle(.disable)
        #expect(locked.phase == .disabled)
        _ = locked.handle(.enable(enrolled: true, camera: .authorized, uptime: 81))
        #expect(locked.phase == .lockedOut)
        #expect(locked.grant == nil)
        _ = locked.handle(.tick(uptime: 80 + FaceVerificationPolicy.lockoutSeconds + 0.001))
        #expect(locked.phase == .idle)
    }

    @Test func everyPhaseStaysInsideItsGuardedSuccessors() {
        let allowed: [FaceVerificationPhase: Set<FaceVerificationPhase>] = [
            .disabled: [.disabled, .notEnrolled, .idle],
            .notEnrolled: [.notEnrolled, .enrolling, .disabled],
            .enrolling: [.enrolling, .idle, .notEnrolled, .disabled],
            .idle: [.idle, .capturing, .enrolling, .notEnrolled, .disabled, .rejected],
            .capturing: [.capturing, .livenessCheck, .rejected, .lockedOut, .fallback, .disabled, .notEnrolled],
            .livenessCheck: [.livenessCheck, .rejected, .lockedOut, .matched, .fallback, .disabled, .notEnrolled],
            .matched: [.matched, .capturing, .disabled, .notEnrolled],
            .rejected: [.rejected, .capturing, .fallback, .disabled, .notEnrolled],
            .lockedOut: [.lockedOut, .idle, .disabled, .notEnrolled],
            .fallback: [.fallback, .idle, .rejected, .lockedOut, .disabled, .notEnrolled],
        ]
        #expect(Set(allowed.keys) == Set(FaceVerificationPhase.allCases))
        let machines = parked()
        #expect(Set(machines.keys) == Set(FaceVerificationPhase.allCases))
        for phase in FaceVerificationPhase.allCases {
            for event in eventCatalog(step: 7) {
                var machine = machines[phase]!
                _ = machine.handle(event)
                #expect(allowed[phase]!.contains(machine.phase), "\(phase) + \(event) -> \(machine.phase)")
            }
        }
    }

    @Test func presenceKeepsItsKeyAndFailsClosedWhileOff() {
        #expect(FacePresenceLink.enabledKey == "face.presence")
        #expect(FacePresenceLink.lockAfterKey == "face.lockAfter")
        #expect(FacePresenceLink.statusKey == "face.status")
        #expect(FacePresenceLink.outcome(enabled: false, presence: .absent) == .unchanged)
        #expect(FacePresenceLink.outcome(enabled: false, presence: .present) == .unchanged)
        #expect(FacePresenceLink.outcome(enabled: true, presence: .absent) == .lock)
        #expect(FacePresenceLink.outcome(enabled: true, presence: .present) == .wake)
        #expect(FacePresenceLink.outcome(enabled: true, presence: .unknown) == .unchanged)
    }

    private func parked() -> [FaceVerificationPhase: FaceVerificationMachine] {
        let disabledDuringNothing = FaceVerificationMachine()
        let notEnrolled = FaceVerificationFixtures.notEnrolled()
        let enrolling = FaceVerificationFixtures.enrolling()
        let idle = FaceVerificationFixtures.idle()
        let capturing = FaceVerificationFixtures.capturing(nonce: "park-capture")
        let checking = FaceVerificationFixtures.liveness(nonce: "park-live")
        let matched = FaceVerificationFixtures.matched(nonce: "park-match")
        let rejected = FaceVerificationFixtures.rejected(nonce: "park-reject")
        let locked = FaceVerificationFixtures.locked()
        let fallback = FaceVerificationFixtures.fallback(nonce: "park-fallback")
        return [
            .disabled: disabledDuringNothing,
            .notEnrolled: notEnrolled,
            .enrolling: enrolling,
            .idle: idle,
            .capturing: capturing,
            .livenessCheck: checking,
            .matched: matched,
            .rejected: rejected,
            .lockedOut: locked,
            .fallback: fallback,
        ]
    }

    private func eventCatalog(step: Int) -> [FaceVerificationEvent] {
        let fresh = FaceVerificationFixtures.action("catalog-\(step)")
        let empty = ApprovalAction(id: "", nonce: "")
        return [
            .enable(enrolled: false, camera: .authorized, uptime: 1),
            .enable(enrolled: true, camera: .authorized, uptime: 1),
            .disable,
            .beginEnrollment,
            .enrollmentSaved(image: nil, thumbnail: nil),
            .enrollmentSaved(image: Data([9]), thumbnail: nil),
            .enrollmentCancelled,
            .deleteTemplate,
            .cameraAnswered(granted: true),
            .cameraAnswered(granted: false),
            .beginApproval(fresh, uptime: 3),
            .beginApproval(empty, uptime: 3),
            .capture(.seen(distance: 0, spoof: [], virtualCamera: false), uptime: 4),
            .capture(.seen(distance: 0, spoof: [.glossGlare], virtualCamera: false), uptime: 4),
            .capture(.lowLight, uptime: 4),
            .capture(.tooFar, uptime: 4),
            .capture(.tooNear, uptime: 4),
            .capture(.occluded, uptime: 4),
            .capture(.noCamera, uptime: 4),
            .capture(.timeout, uptime: 4),
            .capture(.noFace, uptime: 4),
            .liveness(FaceLivenessResult(blinked: true, turnedHead: false, virtualCamera: false), uptime: 5),
            .liveness(FaceLivenessResult(blinked: false, turnedHead: false, virtualCamera: false), uptime: 5),
            .identity(matched: true, uptime: 6),
            .identity(matched: false, uptime: 6),
            .chooseFallback,
            .fallbackResult(succeeded: true, action: fresh, uptime: 7),
            .fallbackResult(succeeded: false, action: fresh, uptime: 7),
            .tick(uptime: 0),
            .tick(uptime: 10_000),
        ]
    }
}
