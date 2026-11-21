import CryptoKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Disposable defaults and MemoryKeychain only. No system Keychain, hardware ID or server access.
@MainActor @Suite("License credential cleanup")
struct LicenseCredentialCleanupTests {
    private func manager(_ backend: MemoryKeychain, _ defaults: UserDefaults) -> LicenseManager {
        // An explicit empty fixture URL overrides any bundled production server default.
        defaults.set("", forKey: "license.server")
        return LicenseManager(defaults: defaults, credentials: KeychainStore(backend: backend, defaults: defaults),
                       deviceID: "synthetic-device", trustedKeys: [], synchronizeAtLaunch: false)
    }

    private actor Server: LicenseServerServing {
        let response: Result<String, LicenseError>
        let delayed: Bool
        var activationStarted = false
        private var release: CheckedContinuation<Void, Never>?
        init(response: Result<String, LicenseError>, delayed: Bool = false) {
            self.response = response; self.delayed = delayed
        }
        func activate(key: String, device: String, name: String) async -> Result<String, LicenseError> {
            activationStarted = true
            if delayed { await withCheckedContinuation { release = $0 } }
            return response
        }
        func finishActivation() { release?.resume(); release = nil }
        func deactivate(key: String, device: String) async -> Result<Void, LicenseError> { .success(()) }
        func revocations() async -> Result<String, LicenseError> { .failure(.server("Synthetic server")) }
    }

    private func signedFixture(_ name: String, _ serverResponse: ((String) -> Server)) throws
        -> (UserDefaults, MemoryKeychain, LicenseManager, String, Server) {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set("https://synthetic-license.invalid", forKey: "license.server")
        defaults.set(true, forKey: "license.activationPending")
        let signer = Curve25519.Signing.PrivateKey()
        let key = try License.encode(.init(id: "synthetic-license", email: "fixture@example.invalid",
                                           plan: "lifetime", issued: 1), signingKey: signer)
        let proof = try SignedBlob.encode(ActivationPayload(license: "synthetic-license", device: "synthetic-device",
                                                            issued: 1, seat: 1, seats: 1),
                                         prefix: ActivationPayload.prefix, signingKey: signer)
        // The server address is only trusted with a Keychain binding the owner saved in Settings.
        let backend = MemoryKeychain(["com.zeus.app|license.key": key,
                                      "com.zeus.app|\(LicenseManager.serverOriginAccount)": "https://synthetic-license.invalid:443"])
        let server = serverResponse(proof)
        let manager = LicenseManager(defaults: defaults, credentials: KeychainStore(backend: backend, defaults: defaults),
                                     deviceID: "synthetic-device", trustedKeys: [signer.publicKey], synchronizeAtLaunch: false,
                                     serverFactory: { _ in server }, deviceName: { "Synthetic Mac" })
        return (defaults, backend, manager, key, server)
    }

    @Test func partialDeletionKeepsRetryAcrossRelaunchAndDoesNotReactivateRetainedCredentials() async throws {
        let name = NSTemporaryDirectory() + "zeus.license-cleanup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = MemoryKeychain(["com.zeus.app|license.key": "synthetic-key",
                                      "com.zeus.app|license.activation": "synthetic-proof"])
        let first = manager(backend, defaults)
        backend.locked = ["com.zeus.app|license.activation"]
        #expect(await first.deactivate() != nil)
        #expect(first.deactivationError != nil)
        #expect(!first.isLicensed)
        #expect(!first.busy)
        #expect(defaults.bool(forKey: "license.cleanupPending"))
        #expect(!defaults.bool(forKey: "license.activationPending"))
        #expect(backend.items["com.zeus.app|license.key"] == nil)
        #expect(backend.items["com.zeus.app|license.activation"] == "synthetic-proof")

        let relaunched = manager(backend, defaults)
        #expect(relaunched.deactivationError != nil)
        #expect(!relaunched.activationPending)
        // New activation must not overwrite credentials whose explicit cleanup is unfinished.
        #expect(await relaunched.activate("synthetic-replacement") != nil)
        #expect(backend.items["com.zeus.app|license.key"] == nil)
        backend.locked = []
        #expect(await relaunched.deactivate() == nil)
        #expect(relaunched.deactivationError == nil)
        #expect(!defaults.bool(forKey: "license.cleanupPending"))
        #expect(backend.items["com.zeus.app|license.activation"] == nil)
        #expect(manager(backend, defaults).deactivationError == nil)
    }

    @Test func deniedKeyDeletionRemainsInactiveAndRetryableUntilConfirmedRemoval() async throws {
        let name = NSTemporaryDirectory() + "zeus.license-cleanup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = MemoryKeychain(["com.zeus.app|license.key": "synthetic-key"])
        let first = manager(backend, defaults)
        backend.locked = ["com.zeus.app|license.key"]
        #expect(await first.deactivate() != nil)
        #expect(first.deactivationError != nil)
        #expect(backend.items["com.zeus.app|license.key"] == "synthetic-key")
        #expect(defaults.bool(forKey: "license.cleanupPending"))
        backend.locked = []
        let relaunched = manager(backend, defaults)
        #expect(relaunched.deactivationError != nil)
        #expect(!relaunched.activationPending)
        #expect(await relaunched.deactivate() == nil)
        #expect(backend.items["com.zeus.app|license.key"] == nil)
        #expect(!defaults.bool(forKey: "license.cleanupPending"))
    }

    @Test func delayedBackgroundActivationCannotRestoreCredentialsAfterExplicitDeactivation() async throws {
        let name = NSTemporaryDirectory() + "zeus.license-cleanup.\(UUID().uuidString)"
        let (defaults, backend, manager, _, server) = try signedFixture(name) { Server(response: .success($0), delayed: true) }
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(manager.isLicensed && manager.activationPending)
        let background = Task { await manager.syncWithServer(force: true) }
        defer { background.cancel(); Task { await server.finishActivation() } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await server.activationStarted), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(await server.activationStarted)
        #expect(await manager.deactivate() == nil)
        await server.finishActivation()
        await background.value
        #expect(backend.items["com.zeus.app|license.key"] == nil)
        #expect(backend.items["com.zeus.app|license.activation"] == nil)
        #expect(!manager.isLicensed && !manager.activationPending)
    }

    @Test func offlineRetryOfRefusedKeyNeverReportsSuccessfulReactivation() async throws {
        let name = NSTemporaryDirectory() + "zeus.license-cleanup.\(UUID().uuidString)"
        let (defaults, _, manager, key, _) = try signedFixture(name) { _ in
            Server(response: .failure(.server("Can't reach the synthetic license server.")))
        }
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "license.activationRejected")
        manager.refresh()
        #expect(!manager.isLicensed)
        #expect(await manager.activate(key) != nil)
        #expect(manager.lastError != nil)
        #expect(!manager.isLicensed && manager.activationPending)
        #expect(defaults.bool(forKey: "license.activationRejected"))
    }

    @Test func failedKeyWriteRollsTheProofBackAndDoesNotKeepTheNewProof() async throws {
        let name = NSTemporaryDirectory() + "zeus.license-commit.\(UUID().uuidString)"
        let (defaults, backend, key, proof) = try commitFixture(name)
        defer { defaults.removePersistentDomain(forName: name) }
        backend.items["com.zeus.app|license.key"] = "previous-key"
        backend.items["com.zeus.app|license.activation"] = "previous-proof"
        backend.failWrites = ["license.key"]
        let holder = try signedManager(defaults, backend, Server(response: .success(proof)))
        let message = await holder.manager.activate(key)
        #expect(message != nil)
        #expect(holder.backend.items["com.zeus.app|license.activation"] == "previous-proof")
        #expect(holder.backend.items["com.zeus.app|license.key"] == "previous-key")
    }

    @Test func failedRollbackBlocksTheKeyThatRemains() async throws {
        let name = NSTemporaryDirectory() + "zeus.license-commit.\(UUID().uuidString)"
        let (defaults, backend, key, proof) = try commitFixture(name)
        defer { defaults.removePersistentDomain(forName: name) }
        backend.items["com.zeus.app|license.key"] = key
        backend.items["com.zeus.app|license.activation"] = "previous-proof"
        backend.failWrites = ["license.key"]
        backend.writesLeft["license.activation"] = 1
        let holder = try signedManager(defaults, backend, Server(response: .success(proof)))
        #expect(holder.manager.isLicensed)
        let message = await holder.manager.activate(key)
        #expect(message != nil)
        #expect(!holder.manager.isLicensed)
        #expect(holder.backend.items["com.zeus.app|license.key"] == key)
        #expect(holder.backend.items["com.zeus.app|license.activationRejected"] == LicenseCredentialCommit.blockAll)
    }

    @Test func serverRefusalStaysWithTheKeyAfterTheDefaultsFlagIsCleared() async throws {
        let name = NSTemporaryDirectory() + "zeus.license-commit.\(UUID().uuidString)"
        let (defaults, backend, key, _) = try commitFixture(name)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "license.activationPending")
        backend.items["com.zeus.app|license.key"] = key
        backend.failDeletes = ["license.key"]
        let holder = try signedManager(defaults, backend, Server(response: .failure(.seatsFull)))
        #expect(holder.manager.isLicensed)
        await holder.manager.syncWithServer(force: true)
        #expect(!holder.manager.isLicensed)
        #expect(holder.manager.activationPending)
        #expect(!defaults.bool(forKey: "license.cleanupPending"))
        #expect(holder.backend.items["com.zeus.app|license.key"] == key)
        #expect(holder.backend.items["com.zeus.app|license.activationRejected"] == "synthetic-license")
        defaults.removeObject(forKey: "license.activationRejected")
        let relaunched = try signedManager(defaults, backend, Server(response: .failure(.seatsFull)))
        #expect(!relaunched.manager.isLicensed)
        #expect(relaunched.backend.items["com.zeus.app|license.key"] == key)
    }

    @Test func aRefusalThatCannotBeStoredStillFailsClosedUntilCleanup() async throws {
        let name = NSTemporaryDirectory() + "zeus.license-commit.\(UUID().uuidString)"
        let (defaults, backend, key, _) = try commitFixture(name)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "license.activationPending")
        backend.items["com.zeus.app|license.key"] = key
        backend.failDeletes = ["license.key"]
        backend.failWrites = [LicenseCredentialCommit.refusalAccount]
        let holder = try signedManager(defaults, backend, Server(response: .failure(.revoked)))
        await holder.manager.syncWithServer(force: true)
        #expect(!holder.manager.isLicensed)
        #expect(defaults.bool(forKey: "license.cleanupPending"))
        #expect(holder.backend.items["com.zeus.app|license.key"] == key)
        defaults.removeObject(forKey: "license.activationRejected")
        let relaunched = try signedManager(defaults, backend, Server(response: .failure(.revoked)))
        #expect(!relaunched.manager.isLicensed)
    }

    @Test func aRevokedKeyStaysOffWhenTheStoredListCannotBeRead() throws {
        let name = NSTemporaryDirectory() + "zeus.license-revocation.\(UUID().uuidString)"
        let (defaults, backend, key, _) = try commitFixture(name)
        defer { defaults.removePersistentDomain(forName: name) }
        backend.items["com.zeus.app|license.key"] = key
        backend.items["com.zeus.app|\(LicenseRevocationPolicy.keychainAccount)"] = "synthetic-license"
        defaults.set("ZEUSR1.not-a-list", forKey: "license.revocations")
        let holder = try signedManager(defaults, backend, Server(response: .failure(.server("Synthetic server"))))
        #expect(!holder.manager.isLicensed)
        defaults.removeObject(forKey: "license.revocations")
        defaults.removeObject(forKey: LicenseRevocationPolicy.defaultsKey)
        let relaunched = try signedManager(defaults, backend, Server(response: .failure(.server("Synthetic server"))))
        #expect(!relaunched.manager.isLicensed)
        #expect(relaunched.backend.items["com.zeus.app|license.key"] == key)
    }

    private func commitFixture(_ name: String) throws -> (UserDefaults, WriteGate, String, String) {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set("https://synthetic-license.invalid", forKey: "license.server")
        let signer = Curve25519.Signing.PrivateKey()
        let key = try License.encode(.init(id: "synthetic-license", email: "fixture@example.invalid",
                                           plan: "lifetime", issued: 1), signingKey: signer)
        let proof = try SignedBlob.encode(ActivationPayload(license: "synthetic-license", device: "synthetic-device",
                                                            issued: 1, seat: 1, seats: 1),
                                         prefix: ActivationPayload.prefix, signingKey: signer)
        let backend = WriteGate(["com.zeus.app|\(LicenseManager.serverOriginAccount)": "https://synthetic-license.invalid:443"])
        backend.signer = signer
        return (defaults, backend, key, proof)
    }

    private func signedManager(_ defaults: UserDefaults, _ backend: WriteGate, _ server: Server) throws -> (manager: LicenseManager, backend: WriteGate) {
        let signer = try #require(backend.signer)
        let manager = LicenseManager(defaults: defaults, credentials: KeychainStore(backend: backend, defaults: defaults),
                                     deviceID: "synthetic-device", trustedKeys: [signer.publicKey], synchronizeAtLaunch: false,
                                     serverFactory: { _ in server }, deviceName: { "Synthetic Mac" })
        return (manager, backend)
    }
}

/// Writes fail or run out on named accounts. Reads stay available, matching a Keychain item that will not update.
private final class WriteGate: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    var items: [String: String]
    var failWrites: Set<String> = []
    var failDeletes: Set<String> = []
    var writesLeft: [String: Int] = [:]
    var signer: Curve25519.Signing.PrivateKey?
    init(_ items: [String: String] = [:]) { self.items = items }

    private static func key(_ service: String, _ account: String) -> String { "\(service)|\(account)" }

    func accounts(service: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let prefix = service + "|"
        return items.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    func read(service: String, account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return items[Self.key(service, account)]
    }

    func write(_ value: String, service: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if failWrites.contains(account) { return false }
        if let left = writesLeft[account] {
            guard left > 0 else { return false }
            writesLeft[account] = left - 1
        }
        items[Self.key(service, account)] = value
        return true
    }

    func delete(service: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if failDeletes.contains(account) { return false }
        items[Self.key(service, account)] = nil
        return true
    }
}
