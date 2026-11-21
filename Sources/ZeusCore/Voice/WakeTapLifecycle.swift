import Foundation

/// What happened when a wake-word tap was asked to come off the input.
public enum WakeTapRemoval: Equatable, Sendable {
    /// A tap was installed and is now gone.
    case removed
    /// Nothing was installed. A second remove is this, and it must not touch the engine.
    case alreadyClear
    /// The tap is still installed. This is the defect: a stopped engine used to take this path.
    case leftInstalled
}

/// Whether the wake-word microphone tap is installed.
///
/// Removal does not ask if the engine is running. A failed `start`, sleep, or a route change
/// stops the engine and leaves the tap in place. A second remove is a no-op so the engine is
/// not asked to remove a tap it does not have.
public struct WakeTapLifecycle: Equatable, Sendable {
    public private(set) var installed = false

    public init() {}

    public mutating func install() {
        installed = true
    }

    public mutating func remove() -> WakeTapRemoval {
        guard installed else { return .alreadyClear }
        installed = false
        return .removed
    }
}
