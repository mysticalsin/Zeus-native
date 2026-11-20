import Foundation

/// Phases of a face check used to approve one action. The feature starts disabled.
public enum FaceVerificationPhase: String, CaseIterable, Equatable, Sendable {
    case disabled
    case notEnrolled
    case enrolling
    case idle
    case capturing
    case livenessCheck
    case matched
    case rejected
    case lockedOut
    case fallback
}

public enum FaceCameraAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

/// One approval. The nonce is the action's own token, so a match cannot be reused.
public struct ApprovalAction: Equatable, Sendable, Hashable {
    public var id: String
    public var nonce: String

    public init(id: String, nonce: String) {
        self.id = id
        self.nonce = nonce
    }

    public var isBound: Bool { !id.isEmpty && !nonce.isEmpty }
}

public enum FaceApprovalMethod: Equatable, Sendable {
    case face
    case localAuthentication
}

public struct FaceApprovalGrant: Equatable, Sendable {
    public var actionID: String
    public var nonce: String
    public var method: FaceApprovalMethod

    public init(actionID: String, nonce: String, method: FaceApprovalMethod) {
        self.actionID = actionID
        self.nonce = nonce
        self.method = method
    }
}

public enum FaceVerificationFailure: String, CaseIterable, Equatable, Sendable {
    case lowLight
    case tooFar
    case tooNear
    case occluded
    case noCamera
    case permissionDenied
    case timeout
    case noFace
}

public struct FaceLivenessResult: Equatable, Sendable {
    public var blinked: Bool
    public var turnedHead: Bool
    public var virtualCamera: Bool

    public init(blinked: Bool, turnedHead: Bool, virtualCamera: Bool) {
        self.blinked = blinked
        self.turnedHead = turnedHead
        self.virtualCamera = virtualCamera
    }

    /// A blink or a head turn counts, and a virtual camera never does.
    public var passed: Bool { (blinked || turnedHead) && !virtualCamera }
}

public enum FaceCaptureReading: Equatable, Sendable {
    case lowLight
    case tooFar
    case tooNear
    case occluded
    case noCamera
    case timeout
    case noFace
    case seen(distance: Float, spoof: Set<SpoofCue>, virtualCamera: Bool)
}

public enum FaceVerificationEvent: Equatable, Sendable {
    case enable(enrolled: Bool, camera: FaceCameraAccess, uptime: Double)
    case disable
    case beginEnrollment
    case enrollmentSaved(image: Data?, thumbnail: Data?)
    case enrollmentCancelled
    case deleteTemplate
    case cameraAnswered(granted: Bool)
    case beginApproval(ApprovalAction, uptime: Double)
    case capture(FaceCaptureReading, uptime: Double)
    case liveness(FaceLivenessResult, uptime: Double)
    case identity(matched: Bool, uptime: Double)
    case chooseFallback
    case fallbackResult(succeeded: Bool, action: ApprovalAction, uptime: Double)
    case tick(uptime: Double)
}

public enum FaceVerificationEffect: Equatable, Sendable {
    case askCameraConsent
    case startCamera
    case stopCamera
    case refuseImage
    case templateDeleted
}

public struct FaceAuditLine: Equatable, Sendable, Codable {
    public enum Result: String, Equatable, Sendable, Codable {
        case allowed
        case refused
        case fallback
        case locked
    }

    public var time: Double
    public var result: Result

    public init(time: Double, result: Result) {
        self.time = time
        self.result = result
    }

    /// Time and result only. A sample, a frame, or a template never reaches this string.
    public func rendered() -> String {
        "time=\(Int(time)) result=\(result.rawValue)"
    }

    private enum CodingKeys: String, CodingKey {
        case time
        case result
    }
}

public struct FaceFallbackOffer: Equatable, Sendable {
    public var touch: Bool
    public var watch: Bool
    public var password: Bool
    /// False while the check is locked. The fallback cannot approve during the lock.
    public var canApproveNow: Bool

    public init(touch: Bool, watch: Bool, password: Bool, canApproveNow: Bool) {
        self.touch = touch
        self.watch = watch
        self.password = password
        self.canApproveNow = canApproveNow
    }
}

public enum FaceVerificationPolicy {
    /// Failed checks before the lock. Pinned by the red test.
    public static let failureLimit = 5
    /// Seconds the lock lasts. The instant at exactly this duration is still locked.
    public static let lockoutSeconds = 60.0
    /// Euclidean distance on unit vectors. Farther than this is rejected.
    public static let acceptDistance: Float = 0.45
}

public enum FaceVerificationCopy {
    public static let title = "Face verification"
    public static let onboarding = """
    Face verification checks that it is you before Zeus approves an action on this Mac. It is not Face ID, and it cannot unlock the login screen. The camera stays off until you turn this on, and the camera indicator is visible whenever the camera is in use. A blink or a head turn is required. A photo, a screen, or a mask can still fool this check, so it is not a guarantee. After repeated failures the check locks. Locking the Mac when you walk away is a separate switch and starts off.
    """
    public static let locked = "The face check is locked. It cannot approve until the lock ends."

    public static func sentence(_ failure: FaceVerificationFailure) -> String {
        switch failure {
        case .lowLight:
            return "The light is too low for a face check. You can approve with Touch ID, Apple Watch, or your password."
        case .tooFar:
            return "Move closer. The face is too far away to check. You can approve with Touch ID, Apple Watch, or your password."
        case .tooNear:
            return "Move back a little. The face is too close to check. You can approve with Touch ID, Apple Watch, or your password."
        case .occluded:
            return "The camera cannot see a full face. Uncover it, or approve with Touch ID, Apple Watch, or your password."
        case .noCamera:
            return "No camera is available for this check. You can approve with Touch ID, Apple Watch, or your password."
        case .permissionDenied:
            return "The camera stays off because permission was denied. You can approve with Touch ID, Apple Watch, or your password."
        case .timeout:
            return "The check timed out before it saw a face. You can approve with Touch ID, Apple Watch, or your password."
        case .noFace:
            return "No face is in view. Step into the frame, or approve with Touch ID, Apple Watch, or your password."
        }
    }

    public static func fallbackOffer(canApproveNow: Bool) -> FaceFallbackOffer {
        FaceFallbackOffer(touch: true, watch: true, password: true, canApproveNow: canApproveNow)
    }
}

public enum FaceVerificationPrivacy {
    public static func crashText(audit: [FaceAuditLine], samples: [[Float]]) -> String {
        render(audit, samples: samples)
    }

    public static func analyticsText(audit: [FaceAuditLine], samples: [[Float]]) -> String {
        render(audit, samples: samples)
    }

    private static func render(_ audit: [FaceAuditLine], samples: [[Float]]) -> String {
        _ = samples
        return audit.map { $0.rendered() }.joined(separator: "\n")
    }
}

public enum FacePresenceLink {
    public static let enabledKey = "face.presence"
    public static let lockAfterKey = "face.lockAfter"
    public static let statusKey = "face.status"
    public static let defaultEnabled = false

    public enum Outcome: Equatable, Sendable {
        case wake
        case lock
        case unchanged
    }

    /// Off does nothing. On, a present face wakes and an absent face locks.
    public static func outcome(enabled: Bool, presence: FacePresenceMachine.Presence) -> Outcome {
        guard enabled else { return .unchanged }
        switch presence {
        case .present: return .wake
        case .absent: return .lock
        case .unknown: return .unchanged
        }
    }
}

public enum FaceVerificationPlacement: Equatable, Sendable {
    case privacyCard(order: Int)
    public static let standard = FaceVerificationPlacement.privacyCard(order: 1)
}

public struct FaceVerificationLayout: Equatable, Sendable {
    public var rowHeight: Double
    public var panelPadding: Double
    public var cardSpacing: Double

    public init(rowHeight: Double, panelPadding: Double, cardSpacing: Double) {
        self.rowHeight = rowHeight
        self.panelPadding = panelPadding
        self.cardSpacing = cardSpacing
    }

    public static let standard = FaceVerificationLayout(rowHeight: 52, panelPadding: 32, cardSpacing: 28)
}

public enum FaceVerificationNativePlan {
    public static let status = "MAC-PENDING"
    public static let steps = [
        "Enroll his face at a normal distance in ordinary room light, with the camera indicator visible.",
        "Approve one bound action with his face, using a blink or a head turn.",
        "Ask another person, a printed photo, and a face on a screen to try the same action.",
        "Repeat in low light, at the wrong distance (too far and too near), with the camera covered, with permission denied, and after a timeout.",
        "Fail the check five times. Confirm the lock still holds at 60 seconds and releases just after that.",
        "During the lock, confirm a face and the fallback cannot approve. After the lock, approve with the fallback.",
        "Delete the saved face in one action and confirm the next check cannot match.",
        "Turn on lock-when-away, leave until the Mac locks, then come back so his face wakes it. The stored key stays face.presence.",
    ]
}

public struct FaceSideEffectProbe: Equatable, Sendable {
    public private(set) var entered = false

    public init() {}

    public mutating func enter() throws {
        entered = true
        throw FaceIsolationError.disabled
    }
}

public enum FaceIsolationError: Error, Equatable, Sendable {
    case disabled
}

public struct FaceLocalResult: Equatable, Sendable {
    public var enrolled: Bool
    public var faceApproved: Bool
    public var fallbackApproved: Bool
    public var presence: FacePresenceMachine.Presence
    public var finishedLocally: Bool

    public init(enrolled: Bool, faceApproved: Bool, fallbackApproved: Bool, presence: FacePresenceMachine.Presence, finishedLocally: Bool) {
        self.enrolled = enrolled
        self.faceApproved = faceApproved
        self.fallbackApproved = fallbackApproved
        self.presence = presence
        self.finishedLocally = finishedLocally
    }
}
