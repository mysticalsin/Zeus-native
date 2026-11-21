import Foundation

/// Window appearance for the welcome guide and Settings. Both read `general.windowTheme`.
public enum WindowAppearance: String, CaseIterable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public static let key = "general.windowTheme"

    /// Light and Dark are exact. Every other stored value follows the Mac, as the welcome guide does.
    public static func resolve(_ stored: String?) -> WindowAppearance {
        WindowAppearance(rawValue: stored ?? "") ?? .system
    }

    /// The welcome guide's cycle: System, then Light, then Dark, then System.
    public func next() -> WindowAppearance {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    public enum Finish: Equatable, Sendable {
        case light
        case dark
    }

    public func finish(systemIsLight: Bool) -> Finish {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemIsLight ? .light : .dark
        }
    }
}
