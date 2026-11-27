import Foundation

/// A confirmation that the person at this Mac approved one face-vault operation.
/// A save proof does not open the vault for reading, and a read proof does not allow a save.
public struct FaceTemplateProof: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case read
        case save
    }

    public let operation: Operation
    public let userPresent: Bool

    public init(operation: Operation, userPresent: Bool) {
        self.operation = operation
        self.userPresent = userPresent
    }

    /// A proof a test builds on its own. It does not ask macOS and it does not open a camera.
    public static func synthetic(_ operation: Operation, userPresent: Bool) -> FaceTemplateProof {
        FaceTemplateProof(operation: operation, userPresent: userPresent)
    }

    public func allows(_ operation: Operation) -> Bool {
        userPresent && self.operation == operation
    }
}
