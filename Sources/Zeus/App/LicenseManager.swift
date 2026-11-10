import AppKit
import CryptoKit
import Foundation
import Observation
import ZeusCore

/// The license, the trial and what they unlock. Keys are checked offline with Ed25519. A license
/// server (the ZEUS Portal) is optional: when one is set, activating claims a seat for this Mac and
/// ZEUS picks up turned-off keys once a day. With no server, nothing ever goes over the network.
@MainActor
@Observable
final class LicenseManager {
    static let shared = LicenseManager()

    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    /// Where a hosted portal will live. Nil until one is set up: keys then work fully offline.
    static let defaultServer: String? = nil
    static let revocationCheckInterval: TimeInterval = 86_400

    private(set) var status: LicenseStatus = .trial(daysLeft: Trial.days)
    private(set) var activation: ActivationPayload?
    /// Activated offline because the server was unreachable; retried at launch.
    private(set) var activationPending = false
    private(set) var lastError: String?
    /// Why the last "free this Mac's seat" failed; nil once it succeeds. The Settings page shows it with a retry.
    private(set) var deactivationError: String?
    private(set) var busy = false
    let deviceID: String
    let evaluator: LicenseEvaluator
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deviceID = LicenseKeys.thisMacDeviceID()
        evaluator = LicenseEvaluator(publicKeys: LicenseKeys.trusted(debug: Self.isDebug), deviceID: deviceID)
        refresh()
        Task { await self.syncWithServer() }
    }

    var isLicensed: Bool { status.isLicensed }

    /// The license server, from Settings (`license.server`) or the built-in default.
    var serverURL: URL? {
        let text = (defaults.string(forKey: "license.server") ?? Self.defaultServer ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let url = URL(string: text), let scheme = url.scheme, ["https", "http"].contains(scheme) else { return nil }
        // Plain http only to this Mac (the local portal).
        if scheme == "http", !["127.0.0.1", "localhost"].contains(url.host ?? "") { return nil }
        return url
    }

    func setServer(_ text: String) {
        defaults.set(text.trimmingCharacters(in: .whitespaces), forKey: "license.server")
        Task { await syncWithServer(force: true) }
    }

    func refresh(now: Date = Date()) {
        if TopBarStyle.isSnapshot { return }
        let key = Keychain.get("license.key")
        status = evaluator.evaluate(.init(key: key, activation: Keychain.get("license.activation"),
                                          revocations: defaults.string(forKey: "license.revocations"),
                                          trialStart: trialStart(), now: now))
        if let payload = status.payload, let token = Keychain.get("license.activation"),
           case .success(let proof) = evaluator.checkActivation(token, licenseID: payload.id) {
            activation = proof
        } else {
            activation = nil
        }
        activationPending = defaults.bool(forKey: "license.activationPending") && status.isLicensed
    }

    /// Checks and stores a key. Returns nil on success or a message to show.
    @discardableResult
    func activate(_ raw: String) async -> String? {
        let key = raw.filter { !$0.isWhitespace }
        busy = true
        defer { busy = false }
        let payload: LicensePayload
        switch License.verify(key, publicKeys: evaluator.publicKeys, deviceID: deviceID) {
        case .success(let p): payload = p
        case .failure(let error): lastError = error.message; return lastError
        }
        if evaluator.isRevoked(payload.id, list: defaults.string(forKey: "license.revocations")) {
            lastError = LicenseError.revoked.message
            return lastError
        }
        var pending = false
        if let server = serverURL {
            switch await LicenseServerClient(base: server).activate(key: key, device: deviceID, name: Host.current().localizedName ?? "Mac") {
            case .success(let token):
                guard case .success = evaluator.checkActivation(token, licenseID: payload.id) else {
                    lastError = "The license server sent a proof ZEUS can't check."
                    return lastError
                }
                Keychain.set(token, for: "license.activation")
            case .failure(let error) where LicenseServerClient.isOffline(error):
                pending = true // Offline: the key is genuine, so keep going and claim the seat later.
            case .failure(let error):
                lastError = error.message
                return lastError
            }
        }
        Keychain.set(key, for: "license.key")
        defaults.set(pending, forKey: "license.activationPending")
        lastError = nil
        deactivationError = nil
        refresh()
        return nil
    }

    /// Frees this Mac so the key can move to another one. When a server is set and the call fails,
    /// the local key stays (the seat is still held) and the message is returned and kept in `lastError`.
    @discardableResult
    func deactivate() async -> String? {
        busy = true
        defer { busy = false }
        if let server = serverURL, let key = Keychain.get("license.key") {
            if case .failure(let error) = await LicenseServerClient(base: server).deactivate(key: key, device: deviceID) {
                let message = "Couldn't free this Mac's seat: \(error.message) The license is still on this Mac."
                lastError = message
                deactivationError = message
                return message
            }
        }
        Keychain.remove("license.key")
        Keychain.remove("license.activation")
        defaults.removeObject(forKey: "license.activationPending")
        lastError = nil
        deactivationError = nil
        refresh()
        return nil
    }

    /// Claims a pending seat and refreshes the revocation list, at most once a day unless forced.
    func syncWithServer(force: Bool = false) async {
        guard !TopBarStyle.isSnapshot, let server = serverURL else { return }
        let client = LicenseServerClient(base: server)
        if activationPending, let key = Keychain.get("license.key") {
            switch await client.activate(key: key, device: deviceID, name: Host.current().localizedName ?? "Mac") {
            case .success(let token):
                Keychain.set(token, for: "license.activation")
                defaults.set(false, forKey: "license.activationPending")
            case .failure(let error) where !LicenseServerClient.isOffline(error):
                // The server refused (seats full, turned off): stop treating this Mac as licensed.
                Keychain.remove("license.key")
                defaults.set(false, forKey: "license.activationPending")
                lastError = error.message
            case .failure:
                break
            }
        }
        let last = defaults.double(forKey: "license.revocationsCheckedAt")
        if force || Date().timeIntervalSince1970 - last > Self.revocationCheckInterval,
           case .success(let list) = await client.revocations(),
           case .success = SignedBlob.decode(list, as: RevocationList.self, prefix: RevocationList.prefix, publicKeys: evaluator.publicKeys) {
            defaults.set(list, forKey: "license.revocations")
            defaults.set(Date().timeIntervalSince1970, forKey: "license.revocationsCheckedAt")
        }
        refresh()
    }

    func setStatusForSnapshot(_ status: LicenseStatus) { self.status = status }

    /// First launch, kept in the Keychain so reinstalling does not restart the trial.
    private func trialStart() -> Date {
        if let text = Keychain.get("trial.start"), let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
        let now = Date()
        Keychain.set(String(now.timeIntervalSince1970), for: "trial.start")
        return now
    }
}

/// The single switch for paid features. Gating is off: everything is unlocked until Tony decides to sell.
@MainActor
enum Entitlements {
    /// Flip to true to require a license after the trial. Lockout is graceful: the notch keeps working.
    static let gatingEnabled = false

    static func allows(_ feature: LicenseGate.Feature) -> Bool {
        LicenseGate.allows(feature, status: LicenseManager.shared.status, gatingEnabled: gatingEnabled)
    }
}
