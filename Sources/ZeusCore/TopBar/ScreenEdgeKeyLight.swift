import Foundation

/// Caps Lock, Shift held on its own, and the command peeks travel around the screen edge.
/// The notch outline flash stays. This names the extra travelling light those keys show.
public enum ScreenEdgeKeyLight {
    public static func tint(for kind: NotchLightKind) -> NotchLightTint? {
        switch kind {
        case .capsLock(let on): return on ? .amber : .white
        case .shiftCrest: return .white
        case .shortcut: return .white
        default: return nil
        }
    }
}
