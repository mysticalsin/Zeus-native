import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Apply at request construction and dispatch, not just in the Settings validation UI.
/// Keys belong in the Keychain, never in a URL persisted in preferences.
public enum AnyLLMEndpointPolicy {
    public static func permits(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host?.lowercased(), !host.isEmpty else { return false }
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return isLoopback(host)
        default: return false
        }
    }

    public static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
    }
}

/// A shared ephemeral connection pool for the explicitly selected endpoint. Redirects are
/// returned as responses, never followed with a user's prompt or credential. The UI can ask
/// the user to save the endpoint's final address instead of silently changing the destination.
public enum AnyLLMHTTPTransport {
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    public static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, AnyLLMEndpointPolicy.permits(url) else { throw URLError(.unsupportedURL) }
        return try await session.data(for: request)
    }
}
