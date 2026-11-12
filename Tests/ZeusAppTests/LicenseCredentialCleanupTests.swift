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
        let backend = MemoryKeychain(["com.zeus.app|license.key": key])
        let server = serverResponse(proof)
        let manager = LicenseManager(defaults: defaults, credentials: KeychainStore(backend: backend, defaults: defaults),
                                     deviceID: "synthetic-device", trustedKeys: [signer.publicKey], synchronizeAtLaunch: false,
                                     serverFactory: { _ in server }, deviceName: { "Synthetic Mac" })
        return (defaults, backend, manager, key, server)
    }

    @Test func partialDeletionKeepsRetryAcrossRelaunchAndDoesNotReactivateRetainedCredentials() async throws {
        let name = "zeus.license-cleanup.\(UUID().uuidString)"
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
        let name = "zeus.license-cleanup.\(UUID().uuidString)"
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
        let name = "zeus.license-cleanup.\(UUID().uuidString)"
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
        let name = "zeus.license-cleanup.\(UUID().uuidString)"
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
}
