import Foundation

/// What a credentialed HTTP client may do with a redirect.
public enum CredentialRedirect {
    public static let sensitiveHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "x-api-key", "xi-api-key", "api-key",
    ]

    /// Red behavior: follow any http(s) redirect and keep every header. The fix refuses a different host
    /// and strips credential headers on the same host.
    public static func forwarded(proposed: URL, from original: URL, headers: [String: String]) -> (url: URL, headers: [String: String])? {
        let scheme = proposed.scheme?.lowercased()
        guard scheme == "https" || scheme == "http" else { return nil }
        return (proposed, headers)
    }
}
