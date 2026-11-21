import Foundation

/// How long a local voice worker may stay silent, and what to do when it will not exit.
/// The first-audio timeout and the 30 s grace already used after a render are the budget.
/// The 20 s and 45 s request timeouts are not involved.
public enum LocalWorkerWatch {
    public static let grace: TimeInterval = 30

    public static func budget(firstAudio: TimeInterval = VoiceTTSChain.firstAudioTimeout) -> TimeInterval {
        firstAudio + grace
    }

    public struct Reap: Equatable, Sendable {
        public var blockFutureLaunches: Bool
        public var holdLaunch: Bool
    }

    /// Red: a child that misses the reap window disables the local voice until relaunch.
    public static func afterReap(exited: Bool) -> Reap {
        Reap(blockFutureLaunches: !exited, holdLaunch: !exited)
    }

    /// Red: a silent worker is never treated as hung.
    public static func hung(started: TimeInterval, now: TimeInterval, budget: TimeInterval) -> Bool {
        false
    }
}
