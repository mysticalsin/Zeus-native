import Foundation

/// Talks to the ZEUS license portal (portal/ in this repo): seat activation, deactivation and the
/// revocation list. Optional: with no server set, licensing is fully offline.
public struct LicenseServerClient: Sendable {
    public let base: URL
    public let session: URLSession

    public init(base: URL, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    struct Reply: Decodable {
        var ok: Bool
        var token: String?
        var list: String?
        var error: String?
        var message: String?
    }

    /// Claims a seat for this Mac and returns the signed activation proof.
    public func activate(key: String, device: String, name: String) async -> Result<String, LicenseError> {
        switch await post("api/v1/activate", ["key": key, "device": device, "name": name]) {
        case .failure(let error): return .failure(error)
        case .success(let reply):
            guard let token = reply.token else { return .failure(.server("The license server sent an empty reply.")) }
            return .success(token)
        }
    }

    /// Frees this Mac's seat.
    public func deactivate(key: String, device: String) async -> Result<Void, LicenseError> {
        (await post("api/v1/deactivate", ["key": key, "device": device])).map { _ in () }
    }

    /// The signed list of turned-off keys.
    public func revocations() async -> Result<String, LicenseError> {
        var request = URLRequest(url: base.appendingPathComponent("api/v1/revocations"))
        request.timeoutInterval = 10
        switch await send(request) {
        case .failure(let error): return .failure(error)
        case .success(let reply):
            guard let list = reply.list else { return .failure(.server("The license server sent an empty reply.")) }
            return .success(list)
        }
    }

    private func post(_ path: String, _ body: [String: String]) async -> Result<Reply, LicenseError> {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return await send(request)
    }

    private func send(_ request: URLRequest) async -> Result<Reply, LicenseError> {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            let success = status.map { (200..<300).contains($0) } ?? false
            guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
                if let status, !success { return .failure(.server("The license server answered with an error (HTTP \(status)).")) }
                return .failure(.server("The license server sent a reply ZEUS can't read."))
            }
            if !reply.ok { return .failure(Self.error(code: reply.error, message: reply.message)) }
            // A reply that claims ok on a non-2xx (or non-HTTP) response is not trusted.
            if !success {
                return .failure(.server(status.map { "The license server answered with an error (HTTP \($0))." } ?? "The license server sent a reply ZEUS can't read."))
            }
            return .success(reply)
        } catch {
            return .failure(.server("Can't reach the license server. Check your connection and try again."))
        }
    }

    static func error(code: String?, message: String?) -> LicenseError {
        switch code {
        case "seats_full": .seatsFull
        case "revoked": .revoked
        case "expired": .expired
        case "unknown_license": .unknownLicense
        case "bad_signature": .badSignature
        case "malformed": .malformed
        default: .server(message ?? "The license server said no.")
        }
    }

    /// True for errors that mean "offline", so activation can wait instead of failing.
    public static func isOffline(_ error: LicenseError) -> Bool {
        if case .server(let text) = error { return text.hasPrefix("Can't reach") }
        return false
    }
}
