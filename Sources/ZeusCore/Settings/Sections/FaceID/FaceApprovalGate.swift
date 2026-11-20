import Foundation

public struct ApprovalSides: Equatable, Sendable {
    public var cardCleared: Bool
    public var terminalCleared: Bool

    public init(cardCleared: Bool, terminalCleared: Bool) {
        self.cardCleared = cardCleared
        self.terminalCleared = terminalCleared
    }

    public static let neither = ApprovalSides(cardCleared: false, terminalCleared: false)

    public var clearedTogether: Bool { cardCleared == terminalCleared }
}

public enum ApprovalFaceGate {
    /// Both sides clear in one decision, and only for a grant bound to this action. A miss clears neither.
    public static func clear(grant: FaceApprovalGrant?, action: ApprovalAction, consumed: Set<String>) -> (sides: ApprovalSides, consumed: Set<String>) {
        guard let grant, action.isBound, grant.actionID == action.id, grant.nonce == action.nonce, !consumed.contains(grant.nonce) else {
            return (.neither, consumed)
        }
        var next = consumed
        next.insert(grant.nonce)
        return (ApprovalSides(cardCleared: true, terminalCleared: true), next)
    }
}

public enum FaceVerificationPipeline {
    /// Enrolment, a face approval, the fallback, and presence. The probes are not called.
    public static func run(network: inout FaceSideEffectProbe, model: inout FaceSideEffectProbe) -> FaceLocalResult {
        if network.entered || model.entered {
            return FaceLocalResult(enrolled: false, faceApproved: false, fallbackApproved: false, presence: .unknown, finishedLocally: false)
        }
        var machine = FaceVerificationMachine()
        _ = machine.handle(.enable(enrolled: false, camera: .authorized, uptime: 1))
        _ = machine.handle(.beginEnrollment)
        _ = machine.handle(.enrollmentSaved(image: nil, thumbnail: nil))
        let faceAction = ApprovalAction(id: "face-action", nonce: "face-nonce")
        _ = machine.handle(.beginApproval(faceAction, uptime: 2))
        _ = machine.handle(.capture(.seen(distance: 0, spoof: [], virtualCamera: false), uptime: 2))
        _ = machine.handle(.liveness(FaceLivenessResult(blinked: true, turnedHead: false, virtualCamera: false), uptime: 2))
        _ = machine.handle(.identity(matched: true, uptime: 2))
        let faceApproved = machine.grant?.method == .face && machine.grant?.nonce == faceAction.nonce
        let fallbackAction = ApprovalAction(id: "fallback-action", nonce: "fallback-nonce")
        _ = machine.handle(.beginApproval(fallbackAction, uptime: 3))
        _ = machine.handle(.capture(.timeout, uptime: 3))
        _ = machine.handle(.chooseFallback)
        _ = machine.handle(.fallbackResult(succeeded: true, action: fallbackAction, uptime: 3))
        let fallbackApproved = machine.grant?.method == .localAuthentication && machine.grant?.nonce == fallbackAction.nonce

        var presenceMachine = FacePresenceMachine()
        _ = presenceMachine.handle(.launch(storedOn: false))
        _ = presenceMachine.handle(.switchOn(
            camera: FacePresenceMachine.CameraAccess.authorized,
            enabledFaces: 1,
            canLock: true,
            vaultReadable: true,
            uptime: 10
        ))
        _ = presenceMachine.handle(.observed(.owner, uptime: 11))
        return FaceLocalResult(
            enrolled: machine.enrolled,
            faceApproved: faceApproved,
            fallbackApproved: fallbackApproved,
            presence: presenceMachine.presence,
            finishedLocally: true
        )
    }
}
