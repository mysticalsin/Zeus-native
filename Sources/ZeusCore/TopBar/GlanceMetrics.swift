import Foundation

/// Numeric tab badges as Glance draws them ("29", "99+"), shown only for counts above zero.
public enum TabBadge {
    public static func text(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}
