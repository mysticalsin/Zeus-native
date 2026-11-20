import Foundation

/// Decides whether a face check may approve one action. It never opens the camera, the network, or a model.
/// Callers carry out the effects. A phase change that leaves the camera also returns `stopCamera`.
public struct FaceVerificationMachine: Equatable, Sendable {
    public private(set) var phase: FaceVerificationPhase = .disabled
    public private(set) var enrolled = false
    public private(set) var failures = 0
    public private(set) var approvalEnabled = false
    public private(set) var camera: FaceCameraAccess = .notDetermined
    public private(set) var grant: FaceApprovalGrant?
    public private(set) var openAction: ApprovalAction?
    public private(set) var audit: [FaceAuditLine] = []
    public private(set) var lastFailure: FaceVerificationFailure?
    public private(set) var fallbackOffer: FaceFallbackOffer?
    public private(set) var livenessPassed = false
    public private(set) var lockoutStarted: Double?
    public private(set) var issuedNonces: Set<String> = []
    private var clock: Double = 0

    public init() {}

    public var wantsCamera: Bool {
        guard approvalEnabled, camera == .authorized else { return false }
        switch phase {
        case .enrolling, .capturing, .livenessCheck: return true
        case .disabled, .notEnrolled, .idle, .matched, .rejected, .lockedOut, .fallback: return false
        }
    }

    public mutating func handle(_ event: FaceVerificationEvent) -> [FaceVerificationEffect] {
        switch event {
        case .enable(let enrolledFlag, let cameraAccess, let uptime):
            stamp(uptime)
            guard phase == .disabled else { return [] }
            approvalEnabled = true
            camera = cameraAccess
            enrolled = enrolledFlag
            if lockActive, !lockReleased(at: uptime) {
                phase = .lockedOut
                fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: false)
                return []
            }
            if lockReleased(at: uptime) { clearLock() }
            phase = enrolledFlag ? .idle : .notEnrolled
            switch cameraAccess {
            case .notDetermined:
                return [.askCameraConsent]
            case .denied:
                lastFailure = .permissionDenied
                fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: true)
                return []
            case .unavailable:
                lastFailure = .noCamera
                fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: true)
                return []
            case .authorized:
                return []
            }

        case .disable:
            let stop = wantsCamera
            approvalEnabled = false
            phase = .disabled
            openAction = nil
            livenessPassed = false
            grant = nil
            fallbackOffer = nil
            lastFailure = nil
            return stop ? [.stopCamera] : []

        case .beginEnrollment:
            guard approvalEnabled, phase == .notEnrolled || phase == .idle, !lockActive else { return [] }
            switch camera {
            case .authorized:
                phase = .enrolling
                return [.startCamera]
            case .notDetermined:
                return [.askCameraConsent]
            case .denied:
                lastFailure = .permissionDenied
                fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: true)
                return []
            case .unavailable:
                lastFailure = .noCamera
                fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: true)
                return []
            }

        case .enrollmentSaved(let image, let thumbnail):
            guard phase == .enrolling else { return [] }
            let stop = stopIfNeeded()
            if image != nil || thumbnail != nil {
                phase = enrolled ? .idle : .notEnrolled
                return [.refuseImage] + stop
            }
            enrolled = true
            phase = .idle
            return stop

        case .enrollmentCancelled:
            guard phase == .enrolling else { return [] }
            let stop = stopIfNeeded()
            phase = enrolled ? .idle : .notEnrolled
            return stop

        case .deleteTemplate:
            let stop = stopIfNeeded()
            enrolled = false
            openAction = nil
            livenessPassed = false
            grant = nil
            if approvalEnabled, phase != .disabled { phase = .notEnrolled }
            return [.templateDeleted] + stop

        case .cameraAnswered(let granted):
            let stop = stopIfNeeded()
            camera = granted ? .authorized : .denied
            guard !granted else { return [] }
            lastFailure = .permissionDenied
            fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: !lockActive)
            if phase == .enrolling {
                phase = enrolled ? .idle : .notEnrolled
                return stop
            }
            if phase == .capturing || phase == .livenessCheck {
                return fail(.permissionDenied, at: clock) + stop
            }
            return []

        case .beginApproval(let action, let uptime):
            stamp(uptime)
            guard approvalEnabled, action.isBound, enrolled, !issuedNonces.contains(action.nonce) else { return [] }
            if lockActive {
                phase = .lockedOut
                fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: false)
                return []
            }
            guard phase == .idle || phase == .rejected || phase == .matched else { return [] }
            switch camera {
            case .authorized:
                openAction = action
                livenessPassed = false
                grant = nil
                phase = .capturing
                return [.startCamera]
            case .notDetermined:
                return [.askCameraConsent]
            case .denied:
                openAction = action
                return fail(.permissionDenied, at: uptime)
            case .unavailable:
                openAction = action
                return fail(.noCamera, at: uptime)
            }

        case .capture(let reading, let uptime):
            stamp(uptime)
            guard phase == .capturing else { return [] }
            switch reading {
            case .seen(let distance, let spoof, let virtualCamera):
                if FaceVerificationMatch.acceptFrame(distance: distance, spoof: spoof, virtualCamera: virtualCamera) {
                    phase = .livenessCheck
                    return []
                }
                return fail(nil, at: uptime)
            case .lowLight: return fail(.lowLight, at: uptime)
            case .tooFar: return fail(.tooFar, at: uptime)
            case .tooNear: return fail(.tooNear, at: uptime)
            case .occluded: return fail(.occluded, at: uptime)
            case .noCamera: return fail(.noCamera, at: uptime)
            case .timeout: return fail(.timeout, at: uptime)
            case .noFace: return fail(.noFace, at: uptime)
            }

        case .liveness(let result, let uptime):
            stamp(uptime)
            guard phase == .livenessCheck else { return [] }
            if result.passed {
                livenessPassed = true
                return []
            }
            livenessPassed = false
            return fail(nil, at: uptime)

        case .identity(let matched, let uptime):
            stamp(uptime)
            guard phase == .livenessCheck else { return [] }
            guard livenessPassed, matched, let action = openAction, action.isBound else {
                if !livenessPassed { return [] }
                return fail(nil, at: uptime)
            }
            let stop = stopIfNeeded()
            phase = .matched
            grant = FaceApprovalGrant(actionID: action.id, nonce: action.nonce, method: .face)
            issuedNonces.insert(action.nonce)
            failures = 0
            lockoutStarted = nil
            audit.append(FaceAuditLine(time: uptime, result: .allowed))
            fallbackOffer = nil
            return stop

        case .chooseFallback:
            guard phase == .capturing || phase == .livenessCheck || phase == .rejected, !lockActive else { return [] }
            let stop = stopIfNeeded()
            phase = .fallback
            fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: true)
            return stop

        case .fallbackResult(let succeeded, let action, let uptime):
            stamp(uptime)
            guard phase == .fallback, !lockActive else { return [] }
            guard succeeded, action.isBound, action == openAction, !issuedNonces.contains(action.nonce) else {
                if !succeeded { return fail(nil, at: uptime) }
                return []
            }
            grant = FaceApprovalGrant(actionID: action.id, nonce: action.nonce, method: .localAuthentication)
            issuedNonces.insert(action.nonce)
            audit.append(FaceAuditLine(time: uptime, result: .fallback))
            failures = 0
            lockoutStarted = nil
            livenessPassed = false
            phase = .idle
            fallbackOffer = nil
            return []

        case .tick(let uptime):
            stamp(uptime)
            guard lockoutStarted != nil else { return [] }
            guard lockReleased(at: uptime) else { return [] }
            clearLock()
            if phase == .lockedOut {
                phase = enrolled && approvalEnabled ? .idle : (approvalEnabled ? .notEnrolled : .disabled)
            }
            return []
        }
    }

    private mutating func stamp(_ uptime: Double) {
        if uptime.isFinite, uptime > clock { clock = uptime }
    }

    private var lockActive: Bool {
        lockoutStarted != nil && failures >= FaceVerificationPolicy.failureLimit
    }

    private func lockReleased(at uptime: Double) -> Bool {
        guard let start = lockoutStarted, uptime >= start else { return false }
        return uptime - start > FaceVerificationPolicy.lockoutSeconds
    }

    private mutating func clearLock() {
        failures = 0
        lockoutStarted = nil
        fallbackOffer = nil
    }

    private func stopIfNeeded() -> [FaceVerificationEffect] {
        wantsCamera ? [.stopCamera] : []
    }

    private mutating func fail(_ reason: FaceVerificationFailure?, at uptime: Double) -> [FaceVerificationEffect] {
        let stop = stopIfNeeded()
        failures += 1
        if let reason { lastFailure = reason }
        livenessPassed = false
        grant = nil
        if failures >= FaceVerificationPolicy.failureLimit {
            phase = .lockedOut
            lockoutStarted = uptime
            fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: false)
            audit.append(FaceAuditLine(time: uptime, result: .locked))
            return stop
        }
        phase = .rejected
        fallbackOffer = FaceVerificationCopy.fallbackOffer(canApproveNow: true)
        audit.append(FaceAuditLine(time: uptime, result: .refused))
        return stop
    }
}
