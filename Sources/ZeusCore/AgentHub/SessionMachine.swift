import Foundation

/// One session, plus the clock a row shows.
///
/// `clockPhase` is the status's phase. `clockGeneration` advances only when the clock starts or restarts.
/// A freeze keeps the generation, and so does a later activity. A new prompt advances it.
/// `previous` is the status stored when an approval begins. Denied and timed out return to it.
public struct HubSessionState: Equatable, Hashable, Sendable {
    public var status: HubSessionStatus
    public var previous: HubSessionStatus?
    public var clockGeneration: Int

    public init(status: HubSessionStatus = .absent, clockGeneration: Int = 0, previous: HubSessionStatus? = nil) {
        self.status = status
        self.clockGeneration = clockGeneration
        self.previous = previous
    }

    public var clockPhase: HubClockPhase? { status.clockPhase }
}

/// The session table as a pure function. The same state and event always return the same next state.
/// A pair that is not in the table comes back unchanged.
///
/// `activity` is the table's "any activity" on a quiet error. A new prompt is `promptStarted`, and it is
/// the only quiet-error event that restarts the clock. The table's guard column is empty, so an approval
/// request from running or waiting enters needsApproval.
public enum HubSessionMachine {
    public static func next(_ state: HubSessionState, _ event: HubSessionEvent) -> HubSessionState {
        switch (state.status, event) {
        case (.absent, .announced):
            return HubSessionState(status: .loading)

        case (.loading, .promptStarted):
            return state.moved(to: .running, restartClock: true)

        case (.loading, .ended),
             (.running, .ended),
             (.waitingForInput, .ended),
             (.needsApproval, .ended),
             (.done, .ended),
             (.error(_), .ended):
            return HubSessionState()

        case (.running, .toolActivity):
            return state

        case (.running, .questionAsked):
            return state.moved(to: .waitingForInput)

        case (.running, .approvalRequested),
             (.waitingForInput, .approvalRequested):
            return state.beginApproval()

        case (.running, .finished),
             (.waitingForInput, .finished):
            return state.moved(to: .done)

        case (.running, .failed),
             (.waitingForInput, .failed):
            return state.moved(to: .error(.failed))

        case (.running, .quietForTheStallLimit):
            return state.moved(to: .error(.quiet))

        case (.waitingForInput, .answerAccepted):
            return state.moved(to: .running)

        case (.needsApproval, .approved):
            return state.moved(to: .running, clearPrevious: true)

        case (.needsApproval, .denied),
             (.needsApproval, .timedOut):
            guard let previous = state.previous else { return state }
            return state.moved(to: previous, clearPrevious: true)

        case (.done, .promptStarted),
             (.error(.failed), .promptStarted),
             (.error(.quiet), .promptStarted):
            return state.moved(to: .running, restartClock: true)

        case (.error(.quiet), .activity):
            return state.moved(to: .running)

        case (.error(.failed), .dismissed):
            return state.moved(to: .done)

        default:
            return state
        }
    }
}

extension HubSessionState {
    fileprivate func moved(
        to status: HubSessionStatus,
        restartClock: Bool = false,
        clearPrevious: Bool = false
    ) -> HubSessionState {
        var copy = self
        copy.status = status
        if restartClock { copy.clockGeneration += 1 }
        if clearPrevious { copy.previous = nil }
        return copy
    }

    /// Stores the status the approval began from, then waits.
    fileprivate func beginApproval() -> HubSessionState {
        var copy = self
        copy.previous = status
        copy.status = .needsApproval
        return copy
    }
}
