import CryptoKit
import Foundation

/// Incremental SHA-256 for files that arrive in chunks.
public struct FlingHasher: Sendable {
    private var hash = SHA256()
    public init() {}
    public mutating func update(_ data: Data) { hash.update(data: data) }
    /// Lowercase hex of everything fed so far; the hasher can keep going afterwards.
    public func finalHex() -> String {
        let copy = hash
        return copy.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct FlingPairSecrets: Equatable, Sendable {
    /// Six digits, shown on both Macs.
    public let code: String
    /// 32 bytes, used as the TLS pre-shared key.
    public let psk: Data
    /// Binds the key and the confirmation to this exact exchange.
    public let transcript: Data
}

public struct FlingPairingEntropy: Sendable {
    public var privateKey: Curve25519.KeyAgreement.PrivateKey
    public var nonce: Data
    public init(privateKey: Curve25519.KeyAgreement.PrivateKey, nonce: Data) { self.privateKey = privateKey; self.nonce = nonce }
    public static func random() -> FlingPairingEntropy {
        var generator = SystemRandomNumberGenerator()
        let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })
        return FlingPairingEntropy(privateKey: Curve25519.KeyAgreement.PrivateKey(), nonce: nonce)
    }
}

/// CryptoKit only: the pairing commitment, the key agreement, the short code, the pre-shared key and the confirmation MAC.
public enum FlingCrypto {
    public static func commitment(pub: Data, nonce: Data) -> Data {
        Data(SHA256.hash(data: pub + nonce))
    }

    /// Lowercase hex SHA-256, the form an offer carries.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func lengthPrefixed(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        var n = UInt32(bytes.count).bigEndian
        return withUnsafeBytes(of: &n) { Data($0) } + bytes
    }

    public static func formatCode(from value: UInt64) -> String {
        String(format: "%06llu", value % 1_000_000)
    }

    /// Both sides call this with the same initiator and responder fields and get the same code, key and transcript.
    public static func secrets(ownPrivate: Curve25519.KeyAgreement.PrivateKey, peerPublic: Data,
                               initiatorID: String, responderID: String,
                               initiatorPublic: Data, responderPublic: Data, nonce: Data) throws -> FlingPairSecrets {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublic)
        let shared = try ownPrivate.sharedSecretFromKeyAgreement(with: peer)
        let transcript = Data(SHA256.hash(data: lengthPrefixed(initiatorID) + lengthPrefixed(responderID) + initiatorPublic + responderPublic + nonce))
        let codeBytes = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript, sharedInfo: Data("zeus-fling-code-v1".utf8), outputByteCount: 8)
            .withUnsafeBytes { Array($0) }
        let value = codeBytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let psk = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript, sharedInfo: Data("zeus-fling-psk-v1".utf8), outputByteCount: 32)
            .withUnsafeBytes { Data($0) }
        return FlingPairSecrets(code: formatCode(from: value), psk: psk, transcript: transcript)
    }

    /// Each side confirms with its own label, so one side's confirmation cannot be echoed back as the other's.
    public static func confirmMAC(psk: Data, transcript: Data, label: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("confirm-\(label)".utf8) + transcript, using: SymmetricKey(data: psk)))
    }

    public static func isValidConfirm(_ mac: Data, psk: Data, transcript: Data, label: String) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data("confirm-\(label)".utf8) + transcript, using: SymmetricKey(data: psk))
    }
}
