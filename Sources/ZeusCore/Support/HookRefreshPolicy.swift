import Foundation

/// What a hook refresh may do to the settings that are already installed.
public enum HookRefreshEffect: Equatable, Sendable {
    case leave
    case rewriteToPublishedPath
}

public enum HookRefreshPolicy {
    /// A failed check leaves the installed text alone. A passing check rewrites only when the
    /// text already names `zeus-hook` and does not name `publishedPath`.
    public static func effect(decision: BundledHelperLaunchDecision, current: String, publishedPath: String) -> HookRefreshEffect {
        guard case .launch = decision else { return .leave }
        let path = publishedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, current.contains("zeus-hook"), !current.contains(path) else { return .leave }
        return .rewriteToPublishedPath
    }
}
