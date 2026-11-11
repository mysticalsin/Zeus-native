/// One slot for work that can be superseded: the newest run wins and a late finish from an older run changes nothing.
///
/// `flag = true; await work; flag = false` is wrong when the work can be started again or cancelled: the cancelled
/// run finishes later and clears the flag under the run that replaced it. A read that started before a write
/// has the same problem, because it lands after the write and puts the old value back. Every run takes a token
/// from `begin()`, a write that makes older reads stale calls `invalidate()`, and only the live token may
/// publish its result or finish.
public struct LatestRun: Equatable, Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var isActive = false

    public init() {}

    /// Starts a run and supersedes every earlier one.
    @discardableResult
    public mutating func begin() -> UInt64 {
        generation &+= 1
        isActive = true
        return generation
    }

    /// True while `token` belongs to the newest run and nothing has invalidated it.
    public func isCurrent(_ token: UInt64) -> Bool { token == generation }

    /// Ends the run that `token` belongs to. False, with no change, when a newer run began or the run was invalidated.
    @discardableResult
    public mutating func finish(_ token: UInt64) -> Bool {
        guard token == generation else { return false }
        isActive = false
        return true
    }

    /// Supersedes work in flight without starting new work: its result is dropped and nothing is active.
    public mutating func invalidate() {
        generation &+= 1
        isActive = false
    }
}
