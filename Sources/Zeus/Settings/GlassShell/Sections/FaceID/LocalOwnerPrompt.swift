import Foundation
import LocalAuthentication
import ZeusCore

/// The platform prompt. Biometrics first, then the password, using one context.
enum LocalOwnerPrompt {
    static func evaluate() async -> FaceOwnerAuthentication {
        let context = LAContext()
        var results: [FaceOwnerAuthentication] = []
        while let policy = FaceOwnerPromptSequence.next(after: results) {
            let result = await evaluate(policy, context: context)
            results.append(result)
            if result == .acceptedBiometrics || result == .acceptedPassword { return result }
        }
        return results.last ?? .refused
    }

    private static func evaluate(_ policy: FaceAuthenticationPolicy, context: LAContext) async -> FaceOwnerAuthentication {
        let la: LAPolicy = policy == .biometrics ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        var error: NSError?
        guard context.canEvaluatePolicy(la, error: &error) else { return .unavailable }
        let reason = "Approve this action"
        do {
            let accepted = try await context.evaluatePolicy(la, localizedReason: reason)
            guard accepted else { return .refused }
            return policy == .biometrics ? .acceptedBiometrics : .acceptedPassword
        } catch {
            return .refused
        }
    }
}
