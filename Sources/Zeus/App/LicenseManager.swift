import AppKit
import CryptoKit
import Foundation
import Observation
import ZeusCore

protocol LicenseServerServing: Sendable {
    func activate(key: String, device: String, name: String) async -> Result<String, LicenseError>
    func deactivate(key: String, device: String) async -> Result<Void, LicenseError>
    func revocations() async -> Result<String, LicenseError>
}

extension LicenseServerClient: LicenseServerServing {}

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
    private let credentials: KeychainStore
    private let serverFactory: @Sendable (URL) -> any LicenseServerServing
    private let deviceName: @Sendable () -> String
    private var credentialRevision: UInt64 = 0

    init(defaults: UserDefaults = .standard, credentials: KeychainStore? = nil,
         deviceID: String? = nil, trustedKeys: [Curve25519.Signing.PublicKey]? = nil,
         synchronizeAtLaunch: Bool = true,
         serverFactory: @escaping @Sendable (URL) -> any LicenseServerServing = { LicenseServerClient(base: $0) },
         deviceName: @escaping @Sendable () -> String = { Host.current().localizedName ?? "Mac" }) {
        self.defaults = defaults
        self.credentials = credentials ?? Keychain.store
        self.serverFactory = serverFactory
        self.deviceName = deviceName
        let resolvedDeviceID = deviceID ?? LicenseKeys.thisMacDeviceID()
        self.deviceID = resolvedDeviceID
        evaluator = LicenseEvaluator(publicKeys: trustedKeys ?? LicenseKeys.trusted(debug: Self.isDebug), deviceID: resolvedDeviceID)
        if defaults.bool(forKey: "license.cleanupPending") {
            deactivationError = "Local license credential cleanup is unfinished. Check Keychain access and try again."
            lastError = deactivationError
        }
        refresh()
        if synchronizeAtLaunch { Task { await self.syncWithServer() } }
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
        credentialRevision &+= 1
        defaults.set(text.trimmingCharacters(in: .whitespaces), forKey: "license.server")
        Task { await syncWithServer(force: true) }
    }

    func refresh(now: Date = Date()) {
        if TopBarStyle.isSnapshot { return }
        let key = credentials.get("license.key")
        status = evaluator.evaluate(.init(key: key, activation: credentials.get("license.activation"),
                                          revocations: defaults.string(forKey: "license.revocations"),
                                          trialStart: trialStart(), now: now,
                                          activationRejected: defaults.bool(forKey: "license.activationRejected") || defaults.bool(forKey: "license.cleanupPending")))
        if let payload = status.payload, let token = credentials.get("license.activation"),
           case .success(let proof) = evaluator.checkActivation(token, licenseID: payload.id) {
            activation = proof
        } else {
            activation = nil
        }
        activationPending = defaults.bool(forKey: "license.activationPending") && key != nil
    }

    /// Checks and stores a key. Returns nil on success or a message to show.
    @discardableResult
    func activate(_ raw: String) async -> String? {
        guard !busy else { return "A license change is already in progress." }
        guard !defaults.bool(forKey: "license.cleanupPending") else {
            return deactivationError ?? "Finish removing the previous local license credentials first."
        }
        let key = raw.filter { !$0.isWhitespace }
        credentialRevision &+= 1
        let revision = credentialRevision
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
            let response = await serverFactory(server).activate(key: key, device: deviceID, name: deviceName())
            guard revision == credentialRevision else { return "License settings changed. Review them and try again." }
            switch response {
            case .success(let token):
                guard case .success = evaluator.checkActivation(token, licenseID: payload.id) else {
                    lastError = "The license server sent a proof Zeus can't check."
                    return lastError
                }
                guard credentials.set(token, for: "license.activation") else {
                    lastError = "Couldn't save the activation proof. Check Keychain access and try again."
                    return lastError
                }
            case .failure(let error) where LicenseServerClient.isOffline(error):
                pending = true // Offline: the key is genuine, so keep going and claim the seat later.
            case .failure(let error):
                lastError = error.message
                return lastError
            }
        }
        let previousKey = credentials.get("license.key")
        if pending, previousKey == key, defaults.bool(forKey: "license.activationRejected") {
            defaults.set(true, forKey: "license.activationPending")
            lastError = "This key was previously refused. The license server is unreachable, so Zeus has not reactivated it. Try again when connected."
            refresh()
            return lastError
        }
        guard credentials.set(key, for: "license.key") else {
            lastError = "Couldn't save the license key. Check Keychain access and try again."
            return lastError
        }
        if !pending || previousKey != key { defaults.removeObject(forKey: "license.activationRejected") }
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
        guard !busy else { return "A license change is already in progress." }
        credentialRevision &+= 1
        let revision = credentialRevision
        busy = true
        defer { busy = false }
        if !defaults.bool(forKey: "license.cleanupPending"), let server = serverURL, let key = credentials.get("license.key") {
            let response = await serverFactory(server).deactivate(key: key, device: deviceID)
            guard revision == credentialRevision else { return "License settings changed. Review them and try again." }
            if case .failure(let error) = response {
                let message = "Couldn't free this Mac's seat: \(error.message) The license is still on this Mac."
                lastError = message
                deactivationError = message
                return message
            }
        }
        // After the server releases the seat, a retry must only finish local cleanup.
        // Persist this before either deletion so relaunch cannot revive a partially removed key.
        defaults.set(true, forKey: "license.cleanupPending")
        defaults.set(false, forKey: "license.activationPending")
        let keyRemoved = credentials.remove("license.key")
        let activationRemoved = credentials.remove("license.activation")
        guard keyRemoved && activationRemoved else {
            let message = "Couldn't remove the local license credentials. Check Keychain access and try again."
            lastError = message
            deactivationError = message
            refresh()
            return message
        }
        defaults.removeObject(forKey: "license.activationPending")
        defaults.removeObject(forKey: "license.activationRejected")
        defaults.removeObject(forKey: "license.cleanupPending")
        lastError = nil
        deactivationError = nil
        refresh()
        return nil
    }

    /// Claims a pending seat and refreshes the revocation list, at most once a day unless forced.
    func syncWithServer(force: Bool = false) async {
        guard !busy, !TopBarStyle.isSnapshot, !defaults.bool(forKey: "license.cleanupPending"), let server = serverURL else { return }
        let revision = credentialRevision
        let client = serverFactory(server)
        if activationPending, let key = credentials.get("license.key") {
            let response = await client.activate(key: key, device: deviceID, name: deviceName())
            guard revision == credentialRevision, !defaults.bool(forKey: "license.cleanupPending"),
                  credentials.get("license.key") == key else { return }
            switch response {
            case .success(let token):
                guard let payload = License.read(key, publicKeys: evaluator.publicKeys),
                      case .success = evaluator.checkActivation(token, licenseID: payload.id) else {
                    lastError = "The license server sent a proof Zeus can't check."
                    refresh()
                    return
                }
                guard credentials.set(token, for: "license.activation") else {
                    lastError = "Couldn't save the activation proof. Check Keychain access and try again."
                    refresh()
                    return
                }
                defaults.set(false, forKey: "license.activationPending")
                defaults.removeObject(forKey: "license.activationRejected")
            case .failure(let error) where !LicenseServerClient.isOffline(error):
                // The server refused (seats full, turned off): stop treating this Mac as licensed.
                defaults.set(true, forKey: "license.activationRejected")
                let removed = credentials.remove("license.key")
                defaults.set(!removed, forKey: "license.activationPending")
                lastError = removed ? error.message : "\(error.message) Couldn't remove the local key. Check Keychain access and retry."
            case .failure:
                break
            }
        }
        let last = defaults.double(forKey: "license.revocationsCheckedAt")
        if force || Date().timeIntervalSince1970 - last > Self.revocationCheckInterval,
           case .success(let list) = await client.revocations(),
           revision == credentialRevision, !defaults.bool(forKey: "license.cleanupPending"),
           case .success = SignedBlob.decode(list, as: RevocationList.self, prefix: RevocationList.prefix, publicKeys: evaluator.publicKeys) {
            defaults.set(list, forKey: "license.revocations")
            defaults.set(Date().timeIntervalSince1970, forKey: "license.revocationsCheckedAt")
        }
        refresh()
    }

    func setStatusForSnapshot(_ status: LicenseStatus) { self.status = status }

    /// First launch, kept in the Keychain so reinstalling does not restart the trial.
    private func trialStart() -> Date {
        if let text = credentials.get("trial.start"), let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
        let now = Date()
        credentials.set(String(now.timeIntervalSince1970), for: "trial.start")
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
