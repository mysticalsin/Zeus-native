import Foundation

/// A configuration/key edit revokes the previous result immediately. Only the current check
/// can enable dispatch; a late answer about an earlier endpoint never approves its replacement.
public struct AnyLLMEndpointValidation: Sendable {
    public enum State: Equatable, Sendable { case idle, testing, passed(String), failed(String) }
    public private(set) var state: State = .idle
    public private(set) var generation: UInt64 = 0
    public var isApproved: Bool { if case .passed = state { true } else { false } }

    public init() {}

    public mutating func invalidate(reason: String? = nil) {
        generation &+= 1
        state = reason.map(State.failed) ?? .idle
    }

    public mutating func begin() -> UInt64? {
        if case .testing = state { return nil }
        generation &+= 1
        state = .testing
        return generation
    }

    @discardableResult
    public mutating func complete(_ result: State, generation token: UInt64) -> Bool {
        guard generation == token, case .testing = state else { return false }
        switch result {
        case .passed, .failed: state = result; return true
        case .idle, .testing: return false
        }
    }
}
