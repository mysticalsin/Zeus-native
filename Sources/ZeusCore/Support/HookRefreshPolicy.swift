import Foundation

/// What a hook refresh may do to the settings that are already installed.
public enum HookRefreshEffect: Equatable, Sendable {
    case leave
    case rewriteToPublishedPath
}

public enum HookRefreshPolicy {
    /// A failed check currently drops the installed hook lines.
    public static func effect(decision: BundledHelperLaunchDecision, current: String, publishedPath: String) -> HookRefreshEffect {
        _ = publishedPath
        guard case .refuse = decision else { return .leave }
        return current.contains("zeus-hook") ? .rewriteToPublishedPath : .leave
    }
}
