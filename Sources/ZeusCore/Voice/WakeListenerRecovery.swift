import Foundation

/// What the wake listener does when capture stops or the input route changes.
/// S10-06. The same tap rule is S02-01; this branch owns `WakeWordListener`.
public enum WakeListenerRecovery {
    public static func stopRemovesTap(engineRunning: Bool) -> Bool {
        _ = engineRunning
        return true
    }

    public static func afterConfigurationChange() -> (removeTap: Bool, dropListener: Bool) {
        (true, true)
    }
}
