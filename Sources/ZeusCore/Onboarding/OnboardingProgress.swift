/// Whether the welcome guide still wants to open by itself.
///
/// Completion used to be the only recorded outcome, and it was written only by the final Sounds step.
/// "Set up later" skipped one step and closing the window recorded nothing, so a person who closed the
/// guide on step three met it again at the saved step on every launch. Dismissed is now a state of its
/// own: the guide stops opening by itself, and "Show setup guide" in Settings still opens it.
public enum OnboardingProgress {
    public enum State: Equatable, Sendable {
        /// Never shown.
        case notStarted
        /// Shown and not yet closed or finished.
        case inProgress
        /// The person closed the guide, or left the last step with "Set up later", before finishing.
        case dismissed
        /// The person finished the last step. Terminal: nothing later demotes it.
        case completed
    }

    public enum Event: Equatable, Sendable {
        case presented
        /// "Set up later" pressed. `onLastStep` is true when no step follows the current one.
        case skippedStep(onLastStep: Bool)
        case windowClosed
        case finished
    }

    public enum Effect: Equatable, Sendable {
        case recordDismissed
        case recordCompleted
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch (state, event) {
        case (.completed, _):
            return (.completed, [])
        case (_, .finished):
            return (.completed, [.recordCompleted])
        case (.dismissed, _):
            return (.dismissed, [])
        case (.notStarted, .presented):
            return (.inProgress, [])
        case (_, .presented):
            return (state, [])
        case (_, .skippedStep(let onLastStep)):
            return onLastStep ? (.dismissed, [.recordDismissed]) : (state, [])
        case (_, .windowClosed):
            return (.dismissed, [.recordDismissed])
        }
    }

    /// The state to start from, given what was saved on disk.
    public static func saved(completed: Bool, dismissed: Bool) -> State {
        if completed { return .completed }
        return dismissed ? .dismissed : .notStarted
    }

    /// Launch policy: the guide opens by itself only when the person has neither finished nor dismissed it.
    /// An explicit `--onboarding-step` request (parity captures) always opens it.
    public static func opensAtLaunch(_ state: State, explicitStepRequested: Bool) -> Bool {
        if explicitStepRequested { return true }
        switch state {
        case .notStarted, .inProgress: return true
        case .dismissed, .completed: return false
        }
    }
}
