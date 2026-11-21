import Foundation

/// Clips the provider player is responsible for.
///
/// An interruption (sleep, route change) drops every live clip even when the file callback never runs.
/// Starting another clip ends the previous one first, so two clips are not live together.
public struct PlaybackClipBook: Equatable, Sendable {
    public private(set) var live: [Int] = []
    private var next = 0

    public init() {}

    public var playing: Bool { !live.isEmpty }

    public mutating func begin() -> Int {
        next += 1
        live.append(next)
        return next
    }

    public mutating func replace() -> Int {
        live.removeAll()
        return begin()
    }

    public mutating func interrupt() {
        live.removeAll()
    }
}
