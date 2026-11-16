import Foundation

/// What a listening turn does when the audio hardware changes under it. A Bluetooth headset that
/// switches between its listening and playback profiles at the moment capture opens stops the
/// engine and changes the input format; the turn must carry on with the new format instead of
/// ending with an empty transcript. Pure decisions and an ordered sequence, so the reaction is
/// testable without audio hardware.
enum CaptureRecovery {
    enum Action: Equatable { case ignore, cancelTurn, rebuild }

    enum Outcome: Equatable, CustomStringConvertible {
        case recovered
        /// The new input has no usable format yet. The next configuration change retries.
        case inputUnavailable
        case restartFailed

        /// Only a failed restart ends the turn: an unusable format may settle on the next notification.
        var endsTurn: Bool { self == .restartFailed }

        var description: String {
            switch self {
            case .recovered: "recovered"
            case .inputUnavailable: "input has no usable format"
            case .restartFailed: "engine would not restart"
            }
        }
    }

    /// A headset settles in two or three changes; more than this is a flapping link, and the turn ends.
    static let maximumChanges = 6
    /// How long to wait before retrying an input that had no usable format.
    static let retryDelay: TimeInterval = 0.4

    static func exceedsLimit(changes: Int) -> Bool { changes > maximumChanges }

    /// A change that belongs to a turn already over (stopped, replaced) is ignored.
    static func action(cancelsTurn: Bool, ownsSession: Bool) -> Action {
        guard ownsSession else { return .ignore }
        return cancelsTurn ? .cancelTurn : .rebuild
    }

    /// Reinstalls the tap on the new format, then restarts the engine the system stopped.
    static func rebuild(reinstallTap: () -> Bool, restartEngine: () throws -> Void) -> Outcome {
        guard reinstallTap() else { return .inputUnavailable }
        do { try restartEngine() } catch { return .restartFailed }
        return .recovered
    }

    /// The whole reaction to one configuration-change notification.
    @discardableResult
    static func handle(cancelsTurn: Bool, ownsSession: Bool,
                       cancelTurn: () -> Void,
                       reinstallTap: () -> Bool,
                       restartEngine: () throws -> Void,
                       recoveryFailed: (Outcome) -> Void) -> Action {
        let action = action(cancelsTurn: cancelsTurn, ownsSession: ownsSession)
        switch action {
        case .ignore:
            break
        case .cancelTurn:
            cancelTurn()
        case .rebuild:
            let outcome = rebuild(reinstallTap: reinstallTap, restartEngine: restartEngine)
            if outcome != .recovered { recoveryFailed(outcome) }
        }
        return action
    }
}
