import CryptoKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The license key is only sent to the server address the owner saved in Settings.
/// Disposable defaults, MemoryKeychain and a recording stub. No network, system Keychain or hardware ID.
@MainActor @Suite("License server binding")
struct LicenseServerBindingTests {
    private actor Recorder: LicenseServerServing {
        private(set) var activations = 0
        private(set) var deactivations = 0
        func activate(key: String, device: String, name: String) async -> Result<String, LicenseError> {
            activations += 1
            return .failure(.server("Can't reach the synthetic license server."))
        }
        func deactivate(key: String, device: String) async -> Result<Void, LicenseError> { deactivations += 1; return .success(()) }
        func revocations() async -> Result<String, LicenseError> { .failure(.server("Synthetic server")) }
    }

    private struct Fixture {
        var defaults: UserDefaults
        var backend: MemoryKeychain
        var manager: LicenseManager
        var recorder: Recorder
        var key: String
        var cleanup: () -> Void
    }

    private func fixture(defaultsServer: String?, boundOrigin: String?) throws -> Fixture {
        let name = "zeus.license-binding.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        if let defaultsServer { defaults.set(defaultsServer, forKey: "license.server") } else { defaults.set("", forKey: "license.server") }
        let signer = Curve25519.Signing.PrivateKey()
        let key = try License.encode(.init(id: "synthetic-license", email: "fixture@example.invalid", plan: "lifetime", issued: 1), signingKey: signer)
        var items = ["com.zeus.app|license.key": key]
        if let boundOrigin { items["com.zeus.app|\(LicenseManager.serverOriginAccount)"] = boundOrigin }
        let backend = MemoryKeychain(items)
        let recorder = Recorder()
        let manager = LicenseManager(defaults: defaults, credentials: KeychainStore(backend: backend, defaults: defaults),
                                     deviceID: "synthetic-device", trustedKeys: [signer.publicKey], synchronizeAtLaunch: false,
                                     serverFactory: { _ in recorder }, deviceName: { "Synthetic Mac" })
        return Fixture(defaults: defaults, backend: backend, manager: manager, recorder: recorder, key: key,
                       cleanup: { defaults.removePersistentDomain(forName: name) })
    }

    @Test func aDefaultsWriteAloneDoesNotNameTheServer() throws {
        let f = try fixture(defaultsServer: "https://collect.example.net", boundOrigin: nil)
        defer { f.cleanup() }
        #expect(f.manager.serverURL == nil)
        #expect(f.manager.serverNeedsReentry, "the Settings page asks the owner to save the address again")
    }

    @Test func aServerTheOwnerSavedIsUsed() throws {
        let f = try fixture(defaultsServer: "https://licenses.example.com", boundOrigin: "https://licenses.example.com:443")
        defer { f.cleanup() }
        #expect(f.manager.serverURL?.host == "licenses.example.com")
        #expect(!f.manager.serverNeedsReentry)
    }

    @Test func aRedirectedDefaultsValueIsIgnored() throws {
        let f = try fixture(defaultsServer: "https://collect.example.net", boundOrigin: "https://licenses.example.com:443")
        defer { f.cleanup() }
        #expect(f.manager.serverURL == nil)
        #expect(f.manager.serverNeedsReentry)
    }

    @Test func noServerSetMeansNothingToReenter() throws {
        let f = try fixture(defaultsServer: nil, boundOrigin: nil)
        defer { f.cleanup() }
        #expect(f.manager.serverURL == nil)
        #expect(!f.manager.serverNeedsReentry)
    }

    @Test func savingTheServerInSettingsBindsItsOrigin() throws {
        let f = try fixture(defaultsServer: nil, boundOrigin: nil)
        defer { f.cleanup() }
        f.manager.setServer("  https://Licenses.Example.com/portal  ")
        #expect(f.backend.items["com.zeus.app|\(LicenseManager.serverOriginAccount)"] == "https://licenses.example.com:443")
        #expect(f.manager.serverURL?.host?.lowercased() == "licenses.example.com")
        #expect(!f.manager.serverNeedsReentry)
    }

    @Test func anAddressThatCannotCarryACredentialIsNotSaved() throws {
        let f = try fixture(defaultsServer: nil, boundOrigin: nil)
        defer { f.cleanup() }
        for bad in ["http://licenses.example.com", "https://user:pw@licenses.example.com", "ftp://licenses.example.com", "licenses.example.com"] {
            f.manager.setServer(bad)
            #expect(f.manager.serverURL == nil, "\(bad)")
            #expect(f.backend.items["com.zeus.app|\(LicenseManager.serverOriginAccount)"] == nil, "\(bad)")
        }
    }

    @Test func clearingTheServerRemovesItsBinding() throws {
        let f = try fixture(defaultsServer: "https://licenses.example.com", boundOrigin: "https://licenses.example.com:443")
        defer { f.cleanup() }
        f.manager.setServer("")
        #expect(f.backend.items["com.zeus.app|\(LicenseManager.serverOriginAccount)"] == nil)
        #expect(f.manager.serverURL == nil)
        #expect(!f.manager.serverNeedsReentry)
    }

    @Test func theLicenseKeyIsNotSentToAnUnboundServer() async throws {
        let f = try fixture(defaultsServer: "https://collect.example.net", boundOrigin: nil)
        defer { f.cleanup() }
        _ = await f.manager.activate(f.key)
        #expect(await f.recorder.activations == 0)
        _ = await f.manager.deactivate()
        #expect(await f.recorder.deactivations == 0)
    }

    @Test func theLicenseKeyIsSentToTheBoundServer() async throws {
        let f = try fixture(defaultsServer: "https://licenses.example.com", boundOrigin: "https://licenses.example.com:443")
        defer { f.cleanup() }
        _ = await f.manager.activate(f.key)
        #expect(await f.recorder.activations == 1)
    }
}
