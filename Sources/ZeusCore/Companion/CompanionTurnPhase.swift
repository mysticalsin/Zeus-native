import Foundation

/// One companion voice turn. Transcribing wears the thinking pose: the notch and the buddy
/// share that meaning, and a flight retargets only speaking.
public enum CompanionTurnPhase: Equatable, Sendable {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
    case interrupted
    case error(String)

    /// Listening, transcribing, thinking and speaking are the in-flight phases. A turn holds one of them.
    public var activePhaseCount: Int {
        switch self {
        case .listening, .transcribing, .thinking, .speaking: 1
        case .idle, .interrupted, .error: 0
        }
    }

    public func pose(flightActive: Bool) -> CompanionTurnPose {
        switch self {
        case .idle: .idle
        case .listening: .listening
        case .transcribing, .thinking: .thinking
        case .speaking: flightActive ? .pointing : .speaking
        case .interrupted: .interrupted
        case .error: .error
        }
    }

    public func notchPose(flightActive: Bool) -> CompanionTurnPose { pose(flightActive: flightActive) }
    public func buddyPose(flightActive: Bool) -> CompanionTurnPose { pose(flightActive: flightActive) }

    public func notchLabel(flightActive: Bool) -> String { pose(flightActive: flightActive).title }
    public func buddyLabel(flightActive: Bool) -> String { pose(flightActive: flightActive).title }
}

/// Poses shared by the notch and the buddy. Pointing is speaking while a flight is active.
public enum CompanionTurnPose: String, Equatable, Sendable, CaseIterable {
    case idle
    case listening
    case thinking
    case speaking
    case pointing
    case interrupted
    case error

    public var title: String {
        switch self {
        case .idle: "Idle"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .pointing: "Pointing"
        case .interrupted: "Interrupted"
        case .error: "Error"
        }
    }
}
