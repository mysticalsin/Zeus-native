import Foundation
import Testing
@testable import ZeusCore

enum FaceVerificationFixtures {
    static func action(_ nonce: String, id: String = "approve-command") -> ApprovalAction {
        ApprovalAction(id: id, nonce: nonce)
    }

    static func enable(_ machine: inout FaceVerificationMachine, enrolled: Bool, camera: FaceCameraAccess = .authorized, at uptime: Double = 0) {
        _ = machine.handle(.enable(enrolled: enrolled, camera: camera, uptime: uptime))
    }

    static func idle(camera: FaceCameraAccess = .authorized) -> FaceVerificationMachine {
        var machine = FaceVerificationMachine()
        enable(&machine, enrolled: true, camera: camera)
        return machine
    }

    static func notEnrolled() -> FaceVerificationMachine {
        var machine = FaceVerificationMachine()
        enable(&machine, enrolled: false)
        return machine
    }

    static func enrolling() -> FaceVerificationMachine {
        var machine = notEnrolled()
        _ = machine.handle(.beginEnrollment)
        return machine
    }

    static func capturing(nonce: String = "nonce-1", at uptime: Double = 10) -> FaceVerificationMachine {
        var machine = idle()
        _ = machine.handle(.beginApproval(action(nonce), uptime: uptime))
        return machine
    }

    static func liveness(nonce: String = "nonce-1", at uptime: Double = 10) -> FaceVerificationMachine {
        var machine = capturing(nonce: nonce, at: uptime)
        _ = machine.handle(.capture(.seen(distance: 0, spoof: [], virtualCamera: false), uptime: uptime))
        return machine
    }

    static func passedLiveness(nonce: String = "nonce-1", at uptime: Double = 10) -> FaceVerificationMachine {
        var machine = liveness(nonce: nonce, at: uptime)
        _ = machine.handle(.liveness(FaceLivenessResult(blinked: true, turnedHead: false, virtualCamera: false), uptime: uptime))
        return machine
    }

    static func matched(nonce: String = "nonce-1", at uptime: Double = 10) -> FaceVerificationMachine {
        var machine = passedLiveness(nonce: nonce, at: uptime)
        _ = machine.handle(.identity(matched: true, uptime: uptime))
        return machine
    }

    static func rejected(nonce: String = "nonce-1", at uptime: Double = 10) -> FaceVerificationMachine {
        var machine = capturing(nonce: nonce, at: uptime)
        _ = machine.handle(.capture(.noFace, uptime: uptime))
        return machine
    }

    static func fallback(nonce: String = "nonce-1", at uptime: Double = 10) -> FaceVerificationMachine {
        var machine = rejected(nonce: nonce, at: uptime)
        _ = machine.handle(.chooseFallback)
        return machine
    }

    /// Fails the open check `count` times. Each failure returns to a state that can start another check.
    static func fail(times count: Int, at uptime: Double = 1_000) -> FaceVerificationMachine {
        var machine = idle()
        for index in 0..<count {
            _ = machine.handle(.beginApproval(action("fail-\(index)"), uptime: uptime))
            _ = machine.handle(.capture(.timeout, uptime: uptime))
        }
        return machine
    }

    static func locked(at uptime: Double = 1_000) -> FaceVerificationMachine {
        fail(times: FaceVerificationPolicy.failureLimit, at: uptime)
    }

    static func freshNonce(step: Int) -> ApprovalAction {
        action("nonce-\(step)")
    }
}
