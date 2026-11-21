import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What a credentialed HTTP client may do with a redirect.
public enum CredentialRedirect {
    public static let sensitiveHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "x-api-key", "xi-api-key", "api-key",
    ]

    public static func forwarded(proposed: URL, from original: URL, headers: [String: String]) -> (url: URL, headers: [String: String])? {
        guard let proposedHost = proposed.host?.lowercased(), !proposedHost.isEmpty,
              let originalHost = original.host?.lowercased(),
              proposedHost == originalHost,
              proposed.user == nil, proposed.password == nil else { return nil }
        let proposedScheme = proposed.scheme?.lowercased()
        let originalScheme = original.scheme?.lowercased()
        if originalScheme == "https" {
            guard proposedScheme == "https" else { return nil }
        } else {
            guard proposedScheme == "http" || proposedScheme == "https" else { return nil }
        }
        let kept = headers.filter { !sensitiveHeaders.contains($0.key.lowercased()) }
        return (proposed, kept)
    }

    public static func apply(to request: URLRequest, original: URL?) -> URLRequest? {
        guard let original, let proposed = request.url,
              let forwarded = forwarded(proposed: proposed, from: original, headers: request.allHTTPHeaderFields ?? [:]) else { return nil }
        var cleaned = request
        cleaned.url = forwarded.url
        cleaned.allHTTPHeaderFields = forwarded.headers
        return cleaned
    }
}

#if canImport(Darwin)
public final class CredentialRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(CredentialRedirect.apply(to: request, original: task.originalRequest?.url ?? response.url))
    }
}
#endif
