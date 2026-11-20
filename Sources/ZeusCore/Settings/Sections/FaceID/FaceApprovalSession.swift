import Foundation

public enum FaceAuthenticationPolicy: Equatable, Sendable {
    /// `deviceOwnerAuthenticationWithBiometrics`
    case biometrics
    /// `deviceOwnerAuthentication`, which can ask for the password.
    case deviceOwner
}

public enum FaceOwnerAuthentication: Equatable, Sendable {
    case acceptedBiometrics
    case acceptedPassword
    case unavailable
    case refused
}

public protocol FaceApprovalAuthenticating {
    mutating func evaluate(_ policy: FaceAuthenticationPolicy) -> FaceOwnerAuthentication
}

public protocol FaceApprovalCameraDriving {
    var access: FaceCameraAccess { get }
    mutating func requestAccessIfNeeded() -> FaceCameraAccess
    mutating func setRunning(_ running: Bool)
}

/// One reading from the existing capture path. No image is carried.
public struct FaceApprovalObservation: Equatable, Sendable {
    public var distance: Float?
    public var spoof: Set<SpoofCue>
    public var virtualCamera: Bool
    public var blinked: Bool
    public var turnedHead: Bool
    public var failure: FaceVerificationFailure?

    public init(distance: Float?, spoof: Set<SpoofCue>, virtualCamera: Bool, blinked: Bool, turnedHead: Bool, failure: FaceVerificationFailure?) {
        self.distance = distance
        self.spoof = spoof
        self.virtualCamera = virtualCamera
        self.blinked = blinked
        self.turnedHead = turnedHead
        self.failure = failure
    }

    public static func failure(_ failure: FaceVerificationFailure) -> FaceApprovalObservation {
        FaceApprovalObservation(distance: nil, spoof: [], virtualCamera: false, blinked: false, turnedHead: false, failure: failure)
    }
}

public enum FaceApprovalFollowUp: Equatable, Sendable {
    case stopped
    case watching
    case authenticateOwner
    case approved(FaceApprovalGrant)
    case none
}

/// Biometrics first. The password policy runs only when biometrics did not accept.
public enum FaceOwnerPromptSequence {
    public static func next(after results: [FaceOwnerAuthentication]) -> FaceAuthenticationPolicy? {
        if results.isEmpty { return .biometrics }
        if results.count == 1, results[0] != .acceptedBiometrics { return .deviceOwner }
        return nil
    }

    public static func run(_ evaluate: (FaceAuthenticationPolicy) -> FaceOwnerAuthentication) -> FaceOwnerAuthentication {
        var results: [FaceOwnerAuthentication] = []
        while let policy = next(after: results) {
            let result = evaluate(policy)
            results.append(result)
            if result == .acceptedBiometrics || result == .acceptedPassword { return result }
        }
        return results.last ?? .refused
    }
}

/// How open an eye is, and how far the nose sits from the eye line. Callers pass numbers, not images.
public enum FaceLivenessSignals {
    public static let closedEye: Float = 0.22
    public static let turned: Float = 0.35

    public static func blinked(eyeAspect: Float?) -> Bool {
        guard let eyeAspect, eyeAspect.isFinite, eyeAspect >= 0 else { return false }
        return eyeAspect < closedEye
    }

    public static func turned(yaw: Float?) -> Bool {
        guard let yaw, yaw.isFinite else { return false }
        return abs(yaw) > turned
    }
}

/// Drives the approval machine from a camera port and an authenticator. Both are injected.
public struct FaceApprovalSession: Equatable, Sendable {
    public private(set) var machine = FaceVerificationMachine()
    public private(set) var enrolled = false

    public init() {}

    public mutating func restore(enabled: Bool, enrolled: Bool, camera: inout some FaceApprovalCameraDriving, at uptime: Double) {
        self.enrolled = enrolled
        guard enabled else { return }
        _ = machine.handle(.enable(enrolled: enrolled, camera: camera.access, uptime: uptime))
    }

    public mutating func setEnabled(_ on: Bool, enrolled: Bool, camera: inout some FaceApprovalCameraDriving, at uptime: Double) {
        self.enrolled = enrolled
        if !on {
            _ = machine.handle(.disable)
            camera.setRunning(false)
            return
        }
        let access = camera.requestAccessIfNeeded()
        _ = machine.handle(.enable(enrolled: enrolled, camera: access, uptime: uptime))
    }

    public mutating func begin(_ action: ApprovalAction, camera: inout some FaceApprovalCameraDriving, at uptime: Double) -> FaceApprovalFollowUp {
        guard machine.approvalEnabled else { return .stopped }
        let effects = machine.handle(.beginApproval(action, uptime: uptime))
        apply(effects, camera: &camera)
        return followUp(stopCamera: &camera)
    }

    public mutating func observe(_ sample: FaceApprovalObservation, camera: inout some FaceApprovalCameraDriving, at uptime: Double) -> FaceApprovalFollowUp {
        if machine.phase == .lockedOut {
            camera.setRunning(false)
            return .authenticateOwner
        }
        if machine.phase == .capturing {
            if let failure = sample.failure {
                _ = machine.handle(.capture(reading(failure), uptime: uptime))
            } else if let distance = sample.distance {
                _ = machine.handle(.capture(.seen(distance: distance, spoof: sample.spoof, virtualCamera: sample.virtualCamera), uptime: uptime))
            } else {
                _ = machine.handle(.capture(.noFace, uptime: uptime))
            }
        }
        if machine.phase == .livenessCheck {
            let life = FaceLivenessResult(blinked: sample.blinked, turnedHead: sample.turnedHead, virtualCamera: sample.virtualCamera)
            _ = machine.handle(.liveness(life, uptime: uptime))
            if machine.livenessPassed,
               let distance = sample.distance,
               FaceVerificationMatch.acceptFrame(distance: distance, spoof: sample.spoof, virtualCamera: sample.virtualCamera) {
                _ = machine.handle(.identity(matched: true, uptime: uptime))
            }
        }
        apply([], camera: &camera)
        if !machine.wantsCamera { camera.setRunning(false) }
        return followUp(stopCamera: &camera)
    }

    public mutating func authenticate<Authenticator: FaceApprovalAuthenticating>(
        using authenticator: inout Authenticator,
        action: ApprovalAction,
        camera: inout some FaceApprovalCameraDriving,
        at uptime: Double
    ) -> FaceApprovalGrant? {
        camera.setRunning(false)
        let outcome = FaceOwnerPromptSequence.run { authenticator.evaluate($0) }
        return finish(outcome, action: action, at: uptime)
    }

    public mutating func finish(_ outcome: FaceOwnerAuthentication, action: ApprovalAction, at uptime: Double) -> FaceApprovalGrant? {
        let accepted = outcome == .acceptedBiometrics || outcome == .acceptedPassword
        _ = machine.handle(.fallbackResult(succeeded: accepted, action: action, uptime: uptime))
        guard accepted, machine.grant?.nonce == action.nonce else { return nil }
        return machine.grant
    }

    private func followUp(stopCamera camera: inout some FaceApprovalCameraDriving) -> FaceApprovalFollowUp {
        if let grant = machine.grant, machine.phase == .matched {
            camera.setRunning(false)
            return .approved(grant)
        }
        switch machine.phase {
        case .capturing, .livenessCheck: return .watching
        case .rejected, .lockedOut, .fallback: return .authenticateOwner
        case .matched: return machine.grant.map { .approved($0) } ?? .none
        case .disabled, .notEnrolled, .idle, .enrolling: return .stopped
        }
    }

    private func apply(_ effects: [FaceVerificationEffect], camera: inout some FaceApprovalCameraDriving) {
        for effect in effects {
            switch effect {
            case .startCamera: camera.setRunning(true)
            case .stopCamera: camera.setRunning(false)
            case .askCameraConsent: _ = camera.requestAccessIfNeeded()
            case .refuseImage, .templateDeleted: break
            }
        }
    }

    private func reading(_ failure: FaceVerificationFailure) -> FaceCaptureReading {
        switch failure {
        case .lowLight: return .lowLight
        case .tooFar: return .tooFar
        case .tooNear: return .tooNear
        case .occluded: return .occluded
        case .noCamera: return .noCamera
        case .permissionDenied: return .noFace
        case .timeout: return .timeout
        case .noFace: return .noFace
        }
    }
}
