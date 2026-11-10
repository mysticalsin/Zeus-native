import CryptoKit
import Foundation

/// What a ZEUS license says. Signed with Ed25519 and checked offline against the embedded public keys.
/// Fields added after v1 (`name`, `seats`) are optional, so every key issued earlier still reads.
public struct LicensePayload: Codable, Equatable, Sendable {
    public var id: String
    public var email: String
    /// One of `LicensePlan`: "lifetime", "annual", "trial", or "pro" for the optional extra tier.
    public var plan: String
    /// Seconds since 1970.
    public var issued: Int
    public var expires: Int?
    /// Bound Mac (see `License.deviceID`), or nil for any Mac.
    public var device: String?
    /// The buyer's name, shown in Settings.
    public var name: String?
    /// How many Macs may activate this key with the license server. Nil means 1.
    public var seats: Int?

    public init(id: String, email: String, plan: String, issued: Int, expires: Int? = nil, device: String? = nil,
                name: String? = nil, seats: Int? = nil) {
        self.id = id; self.email = email; self.plan = plan; self.issued = issued; self.expires = expires; self.device = device
        self.name = name; self.seats = seats
    }

    public var kind: LicensePlan { LicensePlan(rawValue: plan) ?? .lifetime }
    public var seatCount: Int { max(seats ?? 1, 1) }
    public var expiryDate: Date? { expires.map { Date(timeIntervalSince1970: Double($0)) } }
}

public enum LicensePlan: String, CaseIterable, Sendable {
    case lifetime, annual, trial, pro

    public var title: String {
        switch self {
        case .lifetime: "Lifetime license"
        case .annual: "Annual license"
        case .trial: "Trial license"
        case .pro: "ZEUS Pro"
        }
    }
}

public enum LicenseError: Error, Equatable, Sendable {
    case malformed, badSignature, expired, wrongDevice, revoked, seatsFull, unknownLicense, server(String)

    public var message: String {
        switch self {
        case .malformed: "That doesn't look like a ZEUS license key."
        case .badSignature: "This key isn't valid. Check it was pasted in full."
        case .expired: "This license has expired."
        case .wrongDevice: "This key belongs to another Mac. Deactivate it there first."
        case .revoked: "This key was turned off. Contact support for a new one."
        case .seatsFull: "This key is already active on all its Macs. Deactivate it on one of them first."
        case .unknownLicense: "The license server doesn't know this key."
        case .server(let text): text
        }
    }
}

/// Signed blobs share one shape: `<PREFIX>.<json>.<signature>`, both parts base64url.
public enum SignedBlob {
    public static func encode<T: Encodable>(_ value: T, prefix: String, signingKey: Curve25519.Signing.PrivateKey) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(value)
        let signature = try signingKey.signature(for: body)
        return [prefix, License.base64URL(body), License.base64URL(signature)].joined(separator: ".")
    }

    public static func decode<T: Decodable>(_ text: String, as type: T.Type, prefix: String,
                                            publicKeys: [Curve25519.Signing.PublicKey]) -> Result<T, LicenseError> {
        let parts = text.filter { !$0.isWhitespace }.split(separator: ".").map(String.init)
        guard parts.count == 3, parts[0] == prefix, let body = License.data(base64URL: parts[1]),
              let signature = License.data(base64URL: parts[2]) else { return .failure(.malformed) }
        guard publicKeys.contains(where: { $0.isValidSignature(signature, for: body) }) else { return .failure(.badSignature) }
        guard let value = try? JSONDecoder().decode(T.self, from: body) else { return .failure(.malformed) }
        return .success(value)
    }
}

/// License keys look like `ZEUS1.<payload>.<signature>`, both parts base64url.
public enum License {
    public static let prefix = "ZEUS1"

    public static func encode(_ payload: LicensePayload, signingKey: Curve25519.Signing.PrivateKey) throws -> String {
        try SignedBlob.encode(payload, prefix: prefix, signingKey: signingKey)
    }

    public static func verify(_ key: String, publicKey: Curve25519.Signing.PublicKey, deviceID: String,
                              now: Date = Date()) -> Result<LicensePayload, LicenseError> {
        verify(key, publicKeys: [publicKey], deviceID: deviceID, now: now)
    }

    public static func verify(_ key: String, publicKeys: [Curve25519.Signing.PublicKey], deviceID: String,
                              now: Date = Date()) -> Result<LicensePayload, LicenseError> {
        switch SignedBlob.decode(key, as: LicensePayload.self, prefix: prefix, publicKeys: publicKeys) {
        case .failure(let error): return .failure(error)
        case .success(let payload):
            if let expires = payload.expires, Double(expires) < now.timeIntervalSince1970 { return .failure(.expired) }
            if let device = payload.device, device != deviceID { return .failure(.wrongDevice) }
            return .success(payload)
        }
    }

    /// Signature and shape only, ignoring expiry and device, so Settings can say what an expired key was.
    public static func read(_ key: String, publicKeys: [Curve25519.Signing.PublicKey]) -> LicensePayload? {
        try? SignedBlob.decode(key, as: LicensePayload.self, prefix: prefix, publicKeys: publicKeys).get()
    }

    public static func publicKey(base64 text: String) -> Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: text) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    /// A short, stable, non-reversible id for this Mac: SHA-256 of the hardware UUID, first 16 hex digits.
    public static func deviceID(hardwareUUID: String) -> String {
        SHA256.hash(data: Data(hardwareUUID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Short fingerprint of a key, for the server and for support. Not secret, not reversible.
    public static func fingerprint(_ key: String) -> String {
        SHA256.hash(data: Data(key.filter { !$0.isWhitespace }.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func data(base64URL text: String) -> Data? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        // Canonical only: unused low bits in the last character would let one key have many spellings.
        guard let data = Data(base64Encoded: base), base64URL(data) == text else { return nil }
        return data
    }
}

/// Proof from the license server that this Mac holds one of the key's seats: `ZEUSA1.<payload>.<sig>`.
public struct ActivationPayload: Codable, Equatable, Sendable {
    public var license: String
    public var device: String
    public var issued: Int
    public var seat: Int
    public var seats: Int

    public init(license: String, device: String, issued: Int, seat: Int, seats: Int) {
        self.license = license; self.device = device; self.issued = issued; self.seat = seat; self.seats = seats
    }

    public static let prefix = "ZEUSA1"
}

/// The server's signed list of turned-off license ids: `ZEUSR1.<payload>.<sig>`.
public struct RevocationList: Codable, Equatable, Sendable {
    public var issued: Int
    public var ids: [String]

    public init(issued: Int, ids: [String]) { self.issued = issued; self.ids = ids }

    public static let prefix = "ZEUSR1"
}

/// The free trial: 14 days from first launch, then a license is needed (once gating is on).
public enum Trial {
    public static let days = 14

    public static func daysLeft(start: Date, now: Date = Date(), calendar: Calendar = .init(identifier: .gregorian)) -> Int {
        let used = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
        return max(days - used, 0)
    }

    /// Days left until `end`, rounded up, never below zero.
    public static func daysLeft(until end: Date, now: Date = Date()) -> Int {
        max(Int((end.timeIntervalSince(now) / 86_400).rounded(.up)), 0)
    }
}
