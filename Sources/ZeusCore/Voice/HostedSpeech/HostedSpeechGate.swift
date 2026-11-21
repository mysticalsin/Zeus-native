import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Keychain accounts for the hosted speech route. The token never uses any other store.
public enum HostedSpeechAccounts {
    public static let url = "worker.url"
    public static let token = "worker.token"
}

/// The on switch. It is a bool in preferences. The token is not.
public enum HostedSpeechPreference {
    public static let key = "hostedSpeech.enabled"

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? false
    }

    public static func setEnabled(_ on: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key)
    }
}

public enum HostedSpeechRefusal: Equatable, Sendable {
    case notHTTPS
    case missingURL
    case missingToken
    case tokenEmbeddedInURL

    var logName: String {
        switch self {
        case .notHTTPS: "notHTTPS"
        case .missingURL: "missingURL"
        case .missingToken: "missingToken"
        case .tokenEmbeddedInURL: "tokenEmbeddedInURL"
        }
    }
}

/// Off, refused, or ready to call. Ready carries the validated address and never the token.
public enum HostedSpeechPhase: Equatable, Sendable {
    case off
    case refused(HostedSpeechRefusal)
    case ready(URL)
}

/// Explicit phases for the hosted speech route. Off skips every later check.
public enum HostedSpeechGate {
    public static func phase(enabled: Bool, rawURL: String?, token: String?) -> HostedSpeechPhase {
        guard enabled else { return .off }
        guard let rawURL else { return .refused(.missingURL) }
        let address = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if address.isEmpty { return .refused(.notHTTPS) }
        if !secret.isEmpty, address.contains(secret) { return .refused(.tokenEmbeddedInURL) }
        guard let url = URL(string: address),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil
        else { return .refused(.notHTTPS) }
        if secret.isEmpty { return .refused(.missingToken) }
        return .ready(url)
    }
}

public enum HostedSpeechLog {
    /// A single line. The token is not a parameter, so it cannot be written here.
    public static func line(phase: HostedSpeechPhase, host: String?) -> String {
        switch phase {
        case .off:
            return "hosted speech off"
        case .refused(let reason):
            return "hosted speech refused \(reason.logName)"
        case .ready:
            return "hosted speech ready \(host ?? "unknown-host")"
        }
    }
}

public protocol HostedSpeechSecretStore {
    mutating func write(_ value: String, account: String) -> Bool
    func read(_ account: String) -> String?
    mutating func delete(_ account: String) -> Bool
}

public struct HostedSpeechMemoryStore: HostedSpeechSecretStore {
    private var items: [String: String] = [:]

    public init() {}

    public mutating func write(_ value: String, account: String) -> Bool {
        items[account] = value
        return true
    }

    public func read(_ account: String) -> String? { items[account] }

    public mutating func delete(_ account: String) -> Bool {
        items.removeValue(forKey: account) != nil
    }
}

public enum HostedSpeechSetup {
    /// Writes the address and token to the secret store only. Preferences and files are left untouched.
    @discardableResult
    public static func save(url: String, token: String, store: inout some HostedSpeechSecretStore,
                            defaults: UserDefaults, directory: URL) -> HostedSpeechPhase {
        _ = directory
        _ = store.write(url, account: HostedSpeechAccounts.url)
        _ = store.write(token, account: HostedSpeechAccounts.token)
        return HostedSpeechGate.phase(
            enabled: HostedSpeechPreference.isEnabled(defaults),
            rawURL: url,
            token: token
        )
    }
}

public struct HostedSpeechClient {
    public var session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    /// Builds a request only for a ready, enabled route. Every other phase returns before the session.
    @discardableResult
    public func perform(enabled: Bool, rawURL: String?, token: String?, log: inout [String]) -> HostedSpeechPhase {
        let phase = HostedSpeechGate.phase(enabled: enabled, rawURL: rawURL, token: token)
        let host: String?
        if case .ready(let url) = phase { host = url.host } else { host = nil }
        log.append(HostedSpeechLog.line(phase: phase, host: host))
        guard case .ready(let url) = phase else { return phase }
        var request = URLRequest(url: url.appendingPathComponent("tts"))
        request.httpMethod = "POST"
        if let token {
            let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { _, _, _ in done.signal() }
        task.resume()
        _ = done.wait(timeout: .now() + 2)
        return phase
    }
}
