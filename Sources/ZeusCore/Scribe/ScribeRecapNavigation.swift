/// Saved-source navigation must never replace a session that still owns capture or processing.
/// Terminal notes need to be left explicitly or the requested recap remains hidden by that stage.
public enum ScribeRecapNavigation: Equatable, Sendable {
    case unavailable
    case busy
    case open
    case closeNotesAndOpen

    public static func decision(phase: ScribePhase, recapExists: Bool, isCancelled: Bool) -> Self {
        guard recapExists, !isCancelled else { return .unavailable }
        switch phase {
        case .starting, .recording, .ending, .processing: return .busy
        case .complete, .failed: return .closeNotesAndOpen
        case .idle: return .open
        }
    }
}
