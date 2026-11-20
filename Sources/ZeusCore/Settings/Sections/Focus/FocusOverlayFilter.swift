import Foundation

/// An overlay the Focus filter can allow or block. The table is the whole rule.
public enum FocusOverlayKind: String, CaseIterable, Equatable, Sendable {
    case transition
    case timer
    case media
    case notification
    case screenEdge
    case pointingTrail
    case notchCue
}

public struct FocusOverlayRule: Equatable, Sendable {
    public var kind: FocusOverlayKind
    public var allowed: Bool
    /// The notch cue may show a name once reading is allowed. No other overlay does.
    public var showsName: Bool
}

public enum FocusOverlayDecision: Equatable, Sendable {
    /// A Focus is not on, so this filter does not change the overlay.
    case unfiltered
    case allowed
    case blocked
    /// The Focus state cannot be read. Nothing is newly allowed or newly blocked.
    case unavailable
}

public enum FocusOverlayFilter {
    public static let table: [FocusOverlayRule] = [
        FocusOverlayRule(kind: .transition, allowed: true, showsName: false),
        FocusOverlayRule(kind: .timer, allowed: true, showsName: false),
        FocusOverlayRule(kind: .media, allowed: false, showsName: false),
        FocusOverlayRule(kind: .notification, allowed: false, showsName: false),
        FocusOverlayRule(kind: .screenEdge, allowed: false, showsName: false),
        FocusOverlayRule(kind: .pointingTrail, allowed: false, showsName: false),
        FocusOverlayRule(kind: .notchCue, allowed: false, showsName: true),
    ]

    /// Off blocks every overlay while a Focus is on, except the transition overlay when its own switch is on.
    public static func decide(
        kind: FocusOverlayKind, focus: FocusActivity, filterEnabled: Bool, transitionArmed: Bool
    ) -> FocusOverlayDecision {
        switch focus {
        case .unknown:
            return .unavailable
        case .off:
            return .unfiltered
        case .on:
            if !filterEnabled {
                return kind == .transition && transitionArmed ? .allowed : .blocked
            }
            let allowed = table.first { $0.kind == kind }?.allowed ?? false
            return allowed ? .allowed : .blocked
        }
    }
}
