import Foundation

/// Accessibility after it has been granted. The wait list stops polling once access arrives.
/// This watch keeps a sample so a later revoke is visible.
public struct AccessWatch: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case unknown
        case denied
        case granted
    }

    public enum Effect: Equatable, Sendable {
        case granted
        case revoked
    }

    public private(set) var phase: Phase = .unknown

    public init() {}

    public mutating func sample(_ trusted: Bool) -> Effect? {
        switch (phase, trusted) {
        case (.unknown, false), (.denied, false):
            phase = .denied
            return nil
        case (.unknown, true), (.denied, true):
            phase = .granted
            return .granted
        case (.granted, true):
            return nil
        case (.granted, false):
            phase = .denied
            return .revoked
        }
    }
}
