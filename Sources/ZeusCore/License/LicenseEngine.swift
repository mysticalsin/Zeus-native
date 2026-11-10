import CryptoKit
import Foundation

/// Where this Mac stands. Computed from what is saved, with no network and no Keychain access.
public enum LicenseStatus: Equatable, Sendable {
    /// The first-launch trial, no key yet.
    case trial(daysLeft: Int)
    case trialEnded
    /// A valid key. `daysLeft` is set for keys with an end date (trial and annual keys).
    case licensed(LicensePayload, daysLeft: Int?)
    /// A key that was valid and ran out. Treated like an ended trial.
    case expired(LicensePayload)
    /// A key the seller turned off (refund, chargeback, re-issued).
    case revoked(LicensePayload)

    public var isLicensed: Bool { if case .licensed = self { true } else { false } }
    public var payload: LicensePayload? {
        switch self {
        case .licensed(let p, _), .expired(let p), .revoked(let p): p
        case .trial, .trialEnded: nil
        }
    }
}

/// What the saved key, activation proof and revocation list add up to.
public struct LicenseEvaluator: Sendable {
    public let publicKeys: [Curve25519.Signing.PublicKey]
    public let deviceID: String

    public init(publicKeys: [Curve25519.Signing.PublicKey], deviceID: String) {
        self.publicKeys = publicKeys
        self.deviceID = deviceID
    }

    public struct Inputs: Sendable {
        public var key: String?
        public var activation: String?
        public var revocations: String?
        public var trialStart: Date
        public var now: Date
        public init(key: String? = nil, activation: String? = nil, revocations: String? = nil, trialStart: Date, now: Date = Date()) {
            self.key = key; self.activation = activation; self.revocations = revocations; self.trialStart = trialStart; self.now = now
        }
    }

    public func evaluate(_ inputs: Inputs) -> LicenseStatus {
        let trial: LicenseStatus = {
            let left = Trial.daysLeft(start: inputs.trialStart, now: inputs.now)
            return left > 0 ? .trial(daysLeft: left) : .trialEnded
        }()
        guard let key = inputs.key, let payload = License.read(key, publicKeys: publicKeys) else { return trial }
        if isRevoked(payload.id, list: inputs.revocations) { return .revoked(payload) }
        switch License.verify(key, publicKeys: publicKeys, deviceID: deviceID, now: inputs.now) {
        case .success:
            let left = payload.expiryDate.map { Trial.daysLeft(until: $0, now: inputs.now) }
            return .licensed(payload, daysLeft: left)
        case .failure(.expired):
            return .expired(payload)
        case .failure:
            return trial
        }
    }

    /// True when a signed, valid revocation list names this license.
    public func isRevoked(_ id: String, list: String?) -> Bool {
        guard let list, case .success(let revocations) = SignedBlob.decode(list, as: RevocationList.self,
                                                                          prefix: RevocationList.prefix, publicKeys: publicKeys)
        else { return false }
        return revocations.ids.contains(id)
    }

    /// Checks a server's activation proof is genuine and is for this key on this Mac.
    public func checkActivation(_ token: String, licenseID: String) -> Result<ActivationPayload, LicenseError> {
        switch SignedBlob.decode(token, as: ActivationPayload.self, prefix: ActivationPayload.prefix, publicKeys: publicKeys) {
        case .failure(let error): return .failure(error)
        case .success(let activation):
            guard activation.license == licenseID else { return .failure(.unknownLicense) }
            guard activation.device == deviceID else { return .failure(.wrongDevice) }
            return .success(activation)
        }
    }
}

/// The single rule for what each status unlocks. Graceful lockout: the core notch always keeps
/// working; only paid extras stop when the trial or key runs out.
public enum LicenseGate {
    public enum Feature: String, CaseIterable, Sendable { case core, pro, assistant }

    public static func allows(_ feature: Feature, status: LicenseStatus, gatingEnabled: Bool) -> Bool {
        guard gatingEnabled else { return true }
        switch status {
        case .licensed(let payload, _): return feature != .pro || payload.kind == .pro
        case .trial: return true
        case .trialEnded, .expired, .revoked: return feature == .core
        }
    }
}
