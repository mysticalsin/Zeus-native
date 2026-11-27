import Foundation
import LocalAuthentication
import ZeusCore

/// Asks macOS whether the person at this Mac is present, then returns a proof for one vault operation.
/// The reply does not open the camera. A test never calls this; it passes `FaceTemplateProof.synthetic`.
enum FaceSystemPresence {
    private final class Answer: @unchecked Sendable {
        var present = false
        let semaphore = DispatchSemaphore(value: 0)
        func finish(_ success: Bool) {
            present = success
            semaphore.signal()
        }
    }

    @MainActor
    static func proof(for operation: FaceTemplateProof.Operation) -> FaceTemplateProof {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return FaceTemplateProof(operation: operation, userPresent: false)
        }
        let answer = Answer()
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Confirm it is you before Zeus opens the face vault."
        ) { success, _ in
            answer.finish(success)
        }
        let deadline = Date().addingTimeInterval(30)
        while answer.semaphore.wait(timeout: .now()) == .timedOut {
            if Date() >= deadline {
                return FaceTemplateProof(operation: operation, userPresent: false)
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return FaceTemplateProof(operation: operation, userPresent: answer.present)
    }
}
