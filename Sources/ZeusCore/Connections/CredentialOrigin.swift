import Foundation

/// The scheme, host and port a credential was saved for. A key is attached to a request only when
/// the request goes to this exact origin, so changing a stored address cannot redirect a stored key.
public struct CredentialOrigin: Equatable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int

    /// Nil unless `url` can carry a credential: HTTPS (plain HTTP only for this Mac), a host, and no
    /// user name or password in the address. Case, a trailing dot on the host and a default port are
    /// normalised away, so they never make two spellings of one server differ.
    public init?(url: URL) {
        guard url.user == nil, url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil,
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var host = url.host?.lowercased() else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return nil }
        if scheme == "http", !AnyLLMEndpointPolicy.isLoopback(host) { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port ?? (scheme == "https" ? 443 : 80)
    }

    /// Reads back `storedValue` (`https://host:443`). The port is always present and nothing follows it.
    public init?(storedValue: String) {
        guard let components = URLComponents(string: storedValue), components.port != nil,
              components.path.isEmpty, components.query == nil, components.fragment == nil,
              let url = components.url, let origin = CredentialOrigin(url: url) else { return nil }
        self = origin
    }

    /// What is saved next to the key: `scheme://host:port`, IPv6 hosts in brackets.
    public var storedValue: String {
        let shown = host.contains(":") ? "[\(host)]" : host
        return "\(scheme)://\(shown):\(port)"
    }

    public func matches(_ url: URL) -> Bool { CredentialOrigin(url: url) == self }
}

/// Whether a saved secret may go to a request's address.
public enum CredentialBinding {
    public enum State: Equatable, Sendable {
        /// No secret is saved.
        case absent
        /// The secret is bound to this request's origin.
        case ready
        /// A secret is saved but not bound to this origin (saved before binding existed, or the address changed).
        /// Nothing is sent until the owner enters it again for this address.
        case needsReentry
    }

    public static func state(secret: String?, boundOrigin: String?, requestURL: URL?) -> State {
        guard let secret, !secret.isEmpty else { return .absent }
        guard let boundOrigin, let bound = CredentialOrigin(storedValue: boundOrigin),
              let requestURL, bound.matches(requestURL) else { return .needsReentry }
        return .ready
    }

    /// The secret for this request, or nil when there is none or it is bound to another origin.
    public static func credential(secret: String?, boundOrigin: String?, requestURL: URL?) -> String? {
        state(secret: secret, boundOrigin: boundOrigin, requestURL: requestURL) == .ready ? secret : nil
    }
}

extension AnyLLMConfig {
    /// The Keychain account that holds the origin the key was saved for.
    public static let originAccount = "anyllm-api-key.origin"

    /// The origin to store with a key saved while this address is configured; nil when the address
    /// cannot carry a credential (empty, plain HTTP off this Mac, user name in the URL).
    public static func boundOrigin(for config: AnyLLMConfig) -> String? {
        config.chatURL.flatMap(CredentialOrigin.init(url:))?.storedValue
    }

    /// Saves `key` for `origin`. The old origin goes first, then the key, then the new origin, so a failure at any
    /// step leaves the key unbound (never sent) instead of paired with an address it was not saved for.
    /// False when a step failed; whatever is stored is then unbound.
    public static func saveBoundKey(_ key: String, origin: String, in store: KeychainStore) -> Bool {
        store.remove(originAccount) && store.set(key, for: keyAccount) && store.set(origin, for: originAccount)
    }

    public static func credential(secret: String?, boundOrigin: String?, config: AnyLLMConfig) -> String? {
        CredentialBinding.credential(secret: secret, boundOrigin: boundOrigin, requestURL: config.chatURL)
    }

    public static func credentialState(secret: String?, boundOrigin: String?, config: AnyLLMConfig) -> CredentialBinding.State {
        CredentialBinding.state(secret: secret, boundOrigin: boundOrigin, requestURL: config.chatURL)
    }
}
