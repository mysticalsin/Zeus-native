import Foundation
import Testing
@testable import ZeusCore

/// "Allow command-line control": what it covers, where the switch lives, and who may use it.
/// MemoryKeychain and disposable defaults only.
@Suite("Command-line control gate")
struct CLIGateTests {
    // MARK: What is gated

    @Test func everyDebugHookThatCanShowOrRenderPrivatePanelsNeedsTheGate() {
        for name in ["screenshot", "tab", "open-settings", "onboarding", "animate", "presence", "hud-state"] {
            #expect(CLIGate.isSensitive(op: .debug, debugSubcommand: name, argument: ""), "\(name)")
        }
    }

    @Test func theHooksThatAlreadyNeededTheGateStillDo() {
        for name in ["dictate-file", "wake-file", "record", "hands", "hands-live", "selection", "on-device-speech",
                     "import-assistant-key", "engine-logos"] {
            #expect(CLIGate.isSensitive(op: .debug, debugSubcommand: name, argument: ""), "\(name)")
        }
        #expect(CLIGate.isSensitive(op: .debug, debugSubcommand: "screen-share", argument: "on"))
        #expect(!CLIGate.isSensitive(op: .debug, debugSubcommand: "screen-share", argument: "state"))
        for op in [ZeusCommand.Op.listen, .browse, .code, .term] {
            #expect(CLIGate.isSensitive(op: op, debugSubcommand: "", argument: ""))
        }
        #expect(!CLIGate.isSensitive(op: .status, debugSubcommand: "", argument: ""))
    }

    @Test func everyDebugHookIsEitherGatedOrOnTheReviewedOpenList() {
        // A new hook in the catalog fails here until someone decides which side it belongs on.
        let reviewedOpen: Set<String> = ["brain-route", "present", "present-timeline", "update",
                                         "wake-false-triggers", "clean-room", "permissions"]
        for name in DebugSubcommandCatalog.names where !reviewedOpen.contains(name) {
            #expect(CLIGate.isSensitive(op: .debug, debugSubcommand: name, argument: ""), "\(name) is neither gated nor reviewed as open")
        }
        for name in reviewedOpen {
            #expect(DebugSubcommandCatalog.names.contains(name), "\(name) is on the open list but is not a debug hook")
            #expect(!CLIGate.isSensitive(op: .debug, debugSubcommand: name, argument: ""))
        }
    }

    @Test func hooksThatReadFoldersOrChangeLearnedShortcutsNeedTheGate() {
        // second-brain-lookup searches any folder named with --vault and returns snippets, so a program that lacks access to a
        // folder could read it through Zeus. learn lists and undoes the owner's learned shortcuts.
        for name in ["second-brain-lookup", "learn"] {
            #expect(CLIGate.isSensitive(op: .debug, debugSubcommand: name, argument: ""), "\(name)")
            #expect(CLIGate.isSensitive(op: .debug, debugSubcommand: name, argument: "list"), "\(name) list")
        }
    }

    @Test func onlyCaptureHooksStartTheCue() {
        #expect(CLIGate.startsCapture(op: .listen, debugSubcommand: ""))
        #expect(CLIGate.startsCapture(op: .debug, debugSubcommand: "record"))
        #expect(!CLIGate.startsCapture(op: .debug, debugSubcommand: "screenshot"))
        #expect(!CLIGate.startsCapture(op: .ask, debugSubcommand: ""))
    }

    // MARK: Who may use it

    @Test func theGateNeedsBothTheSwitchAndTheBundledProgram() {
        #expect(CLIGate.verdict(gateEnabled: true, peer: { .allow }) == .allowed)
        #expect(CLIGate.verdict(gateEnabled: false, peer: { .allow }) == .gateOff)
        #expect(CLIGate.verdict(gateEnabled: true, peer: { .deny("copied binary") }) == .peerRejected("copied binary"))
        #expect(CLIGate.verdict(gateEnabled: true, peer: { nil }) == .peerRejected("peer not verified"), "no peer information fails closed")
    }

    @Test func theSignatureIsNotReadWhenTheSwitchIsOff() {
        var asked = 0
        _ = CLIGate.verdict(gateEnabled: false, peer: { asked += 1; return .allow })
        #expect(asked == 0)
    }

    // MARK: Where the switch lives

    private func fixture() throws -> (MemoryKeychain, KeychainStore, UserDefaults, () -> Void) {
        let name = "zeus.cli-gate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let backend = MemoryKeychain()
        return (backend, KeychainStore(backend: backend, defaults: defaults), defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func theSwitchIsOffUntilTheOwnerTurnsItOn() throws {
        let (backend, store, _, cleanup) = try fixture()
        defer { cleanup() }
        #expect(!CLIGateStore.isEnabled(store))
        #expect(CLIGateStore.setEnabled(true, keychain: store))
        #expect(CLIGateStore.isEnabled(store))
        #expect(backend.items["com.zeus.app|\(CLIGateStore.account)"] != nil, "it is stored in the Keychain under the app service")
        #expect(CLIGateStore.setEnabled(false, keychain: store))
        #expect(!CLIGateStore.isEnabled(store))
        #expect(backend.items["com.zeus.app|\(CLIGateStore.account)"] == nil)
    }

    @Test func aDefaultsWriteCannotTurnTheSwitchOn() throws {
        let (_, store, defaults, cleanup) = try fixture()
        defer { cleanup() }
        defaults.set(true, forKey: CLIGateStore.legacyDefaultsKey)
        defaults.set(true, forKey: "cli.gate.enabled")
        #expect(!CLIGateStore.isEnabled(store))
    }

    @Test func aFailedKeychainWriteLeavesTheSwitchOff() throws {
        final class Refusing: KeychainBackend, @unchecked Sendable {
            func accounts(service: String) -> [String] { [] }
            func read(service: String, account: String) -> String? { nil }
            func write(_ value: String, service: String, account: String) -> Bool { false }
            func delete(service: String, account: String) -> Bool { true }
        }
        let name = "zeus.cli-gate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = KeychainStore(backend: Refusing(), defaults: defaults)
        #expect(!CLIGateStore.setEnabled(true, keychain: store))
        #expect(!CLIGateStore.isEnabled(store))
    }

    // MARK: The old default

    @Test func anOldTrueValueDoesNotCarryOverAndTheOwnerIsToldOnce() throws {
        let (_, store, defaults, cleanup) = try fixture()
        defer { cleanup() }
        defaults.set(true, forKey: CLIGateStore.legacyDefaultsKey)
        CLIGateStore.migrateLegacy(defaults: defaults)
        #expect(!CLIGateStore.isEnabled(store), "turning it on again is the owner's decision")
        #expect(defaults.object(forKey: CLIGateStore.legacyDefaultsKey) == nil, "the writable copy is removed")
        #expect(CLIGateStore.noticePending(defaults: defaults))
        CLIGateStore.dismissNotice(defaults: defaults)
        #expect(!CLIGateStore.noticePending(defaults: defaults))
        // Running again, or a process writing the old key again, neither enables nor re-shows the notice.
        defaults.set(true, forKey: CLIGateStore.legacyDefaultsKey)
        CLIGateStore.migrateLegacy(defaults: defaults)
        #expect(!CLIGateStore.isEnabled(store))
        #expect(!CLIGateStore.noticePending(defaults: defaults))
    }

    @Test func anOldFalseOrMissingValueShowsNoNotice() throws {
        let (_, _, defaults, cleanup) = try fixture()
        defer { cleanup() }
        CLIGateStore.migrateLegacy(defaults: defaults)
        #expect(!CLIGateStore.noticePending(defaults: defaults))
        let (_, _, other, otherCleanup) = try fixture()
        defer { otherCleanup() }
        other.set(false, forKey: CLIGateStore.legacyDefaultsKey)
        CLIGateStore.migrateLegacy(defaults: other)
        #expect(!CLIGateStore.noticePending(defaults: other))
        #expect(other.object(forKey: CLIGateStore.legacyDefaultsKey) == nil)
    }
}
