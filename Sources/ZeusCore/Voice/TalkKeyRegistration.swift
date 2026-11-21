import Foundation

/// Who is listening for the talk-key notification.
///
/// A preview speaker does not subscribe. A speaker that does subscribe drops its token when it goes away.
public struct TalkKeyRegistration: Equatable, Sendable {
    public private(set) var tokens: [Int] = []
    private var next = 0

    public init() {}

    public mutating func register(subscribes: Bool) -> Int? {
        guard subscribes else { return nil }
        next += 1
        tokens.append(next)
        return next
    }

    public mutating func unregister(_ token: Int?) {
        // Red: the token stays, so every released speaker still hears the talk key.
        _ = token
    }
}
