import Foundation

/// What an event tap does when the system turns it off.
public enum EventTapWatch {
    public enum Notice: Equatable, Sendable {
        case timeout
        case userDisabled
        case event
    }

    public enum Step: Equatable, Sendable {
        case reenable
        case deliver
    }

    public static func step(_ notice: Notice) -> Step {
        switch notice {
        case .timeout, .userDisabled, .event:
            .deliver
        }
    }
}
