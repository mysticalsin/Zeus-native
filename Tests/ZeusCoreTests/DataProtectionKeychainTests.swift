import Foundation
import Testing
#if canImport(Darwin)
@preconcurrency import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#endif
@testable import ZeusCore

/// Records Keychain attributes and the order of calls. Holds no file and calls no Keychain API.
private final class RecordingCredentialKeychain: CredentialKeychain, @unchecked Sendable {
    var legacy: KeychainRead
    var protected: KeychainRead
    var failWrite = false
    var failDelete = false
    var corruptReadBack = false
    var facts: LegacyItemFacts = .zeus
    /// A second legacy item with different bytes. `deleteLegacy(service:account:)` drops every match.
    var sibling: Data?
    let primaryRef = Data("primary-ref".utf8)
    let siblingRef = Data("sibling-ref".utf8)
    private(set) var kinds: [String] = []
    private(set) var writes: [KeychainWriteRequest] = []
    private(set) var log = ""

    init(legacy: KeychainRead = .absent, protected: KeychainRead = .absent) {
        self.legacy = legacy
        self.protected = protected
    }

    func readLegacy(service: String, account: String) -> KeychainRead {
        note("readLegacy")
        return legacy
    }

    func legacyFacts(service: String, account: String) -> LegacyItemFacts { facts }

    func legacyCandidates(service: String, account: String) -> [LegacyCandidate] {
        var list: [LegacyCandidate] = []
        if case .value(let data) = legacy {
            list.append(LegacyCandidate(persistentRef: primaryRef, data: data, facts: facts))
        }
        if let sibling {
            list.append(LegacyCandidate(persistentRef: siblingRef, data: sibling, facts: facts))
        }
        return list
    }

    func deleteLegacyItem(persistentRef: Data) -> Bool {
        note("deleteLegacy")
        if persistentRef == primaryRef, case .value = legacy {
            legacy = .absent
            return true
        }
        if persistentRef == siblingRef, sibling != nil {
            sibling = nil
            return true
        }
        return false
    }

    func readProtected(service: String, account: String) -> KeychainRead {
        note("readProtected")
        if corruptReadBack, case .value = protected { return .value(Data("other-bytes".utf8)) }
        return protected
    }

    func writeProtected(_ data: Data, request: KeychainWriteRequest) -> Bool {
        note("writeProtected")
        writes.append(request)
        guard !failWrite else { return false }
        protected = .value(data)
        return true
    }

    func deleteLegacy(service: String, account: String) -> Bool {
        note("deleteLegacy")
        guard !failDelete else { return false }
        legacy = .absent
        sibling = nil
        return true
    }

    func writeLegacy(_ data: Data, service: String, account: String) -> Bool {
        note("writeLegacy")
        legacy = .value(data)
        return true
    }

    func deleteProtected(service: String, account: String) -> Bool {
        note("deleteProtected")
        protected = .absent
        return true
    }

    private func note(_ step: String) {
        kinds.append(step)
        log += step + "\n"
    }
}

@Suite struct DataProtectionKeychainTests {
    private let secret = Data("synthetic-key-value".utf8)
    private let team = "TEAMID1234"
    private let service = "com.zeus.app"
    private let account = "provider.key"

    @Test func aCredentialWriteUsesTheDataProtectionKeychainAndTheUnlockedClass() throws {
        let request = try #require(CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: team))
        #expect(request.useDataProtectionKeychain)
        #expect(request.accessibility == .whenUnlockedThisDeviceOnly)
        #expect(request.accessGroup == "TEAMID1234.app.zeus.mac")
        #expect(request.updateAttributes == [.accessible(.whenUnlockedThisDeviceOnly)])
        #expect(CredentialKeychainPolicy.entitlementKey == "keychain-access-groups")
        #expect(CredentialKeychainPolicy.entitlementGroup == "$(AppIdentifierPrefix)app.zeus.mac")
    }

    @Test func afterFirstUnlockIsOnlyForAnAccountABackgroundJobNames() {
        #expect(CredentialKeychainPolicy.whileLockedAccounts.isEmpty)
        #expect(CredentialKeychainPolicy.accessibility(account: account) == .whenUnlockedThisDeviceOnly)
        #expect(CredentialKeychainPolicy.accessibility(account: "face.presence.vaultKey") == .whenUnlockedThisDeviceOnly)
        let background: Set<String> = ["scheduled.job"]
        #expect(CredentialKeychainPolicy.accessibility(account: "scheduled.job", whileLocked: background) == .afterFirstUnlockThisDeviceOnly)
        #expect(CredentialKeychainPolicy.accessibility(account: account, whileLocked: background) == .whenUnlockedThisDeviceOnly)
        let request = CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: team)
        #expect(request?.accessibility == .whenUnlockedThisDeviceOnly)
    }

    @Test func aBadTeamIdentifierWritesNothing() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        #expect(CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: "") == nil)
        #expect(CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: "team") == nil)
        #expect(CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: "", keychain: store) == .needsReentry)
        #expect(CredentialKeychainMigration.write(data: secret, service: service, account: account, teamIdentifier: "TEAM-1", keychain: store) == .needsReentry)
        #expect(store.kinds.isEmpty)
        #expect(store.legacy == .value(secret))
    }

    @Test func migrationReadsTheLegacyItemThenWritesThenReadsBackThenDeletes() throws {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .migrated)
        #expect(outcome.state == .available)
        #expect(store.kinds == ["readLegacy", "readProtected", "writeProtected", "readProtected", "deleteLegacy"])
        let write = try #require(store.writes.first)
        #expect(write.useDataProtectionKeychain)
        #expect(write.accessibility == .whenUnlockedThisDeviceOnly)
        #expect(write.accessGroup == "TEAMID1234.app.zeus.mac")
        #expect(store.legacy == .absent)
        #expect(store.protected == .value(secret))
        #expect(secretComesAfterTheVerifyingRead(store.kinds))
        #expect(!store.log.contains("synthetic-key-value"))
        #expect(!CredentialKeychainMigration.logLine(account: account, outcome: outcome).contains("synthetic-key-value"))
    }

    @Test func aSecondRunDeletesALeftoverLegacyItemWithoutWritingAgain() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        #expect(CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store) == .migrated)
        store.legacy = .value(secret)
        let again = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(again == .alreadyProtected)
        #expect(store.writes.count == 1)
        #expect(store.protected == .value(secret))
        #expect(store.legacy == .absent)
        #expect(store.kinds.suffix(4) == ["readLegacy", "readProtected", "readProtected", "deleteLegacy"])
    }

    @Test func anAbsentLegacyItemWithAProtectedCopyOnlyVerifiesAndDeletes() {
        let store = RecordingCredentialKeychain(legacy: .absent, protected: .value(secret))
        let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .alreadyProtected)
        #expect(store.kinds == ["readLegacy", "readProtected", "readProtected", "deleteLegacy"])
        #expect(store.writes.isEmpty)
    }

    @Test func aFailedWriteDoesNotDeleteTheLegacyItem() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.failWrite = true
        let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .needsReentry)
        #expect(outcome.state == .needsReentry)
        #expect(outcome.state.title == "This key needs re-entry")
        #expect(store.kinds == ["readLegacy", "readProtected", "writeProtected"])
        #expect(!store.kinds.contains("deleteLegacy"))
        #expect(store.legacy == .value(secret))
        #expect(!store.log.contains("synthetic-key-value"))
    }

    @Test func aReadBackThatDoesNotMatchDoesNotDeleteOrReturnTheLegacySecret() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.corruptReadBack = true
        let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .needsReentry)
        #expect(store.kinds == ["readLegacy", "readProtected", "writeProtected", "readProtected"])
        #expect(!store.kinds.contains("deleteLegacy"))
        #expect(store.legacy == .value(secret))
        #expect(CredentialKeychainMigration.logLine(account: account, outcome: outcome) == "keychain account=provider.key outcome=needsReentry")
    }

    @Test func aFailedDeleteAfterAVerifiedCopyDoesNotClaimSuccess() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.failDelete = true
        let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .needsReentry)
        #expect(store.kinds.last == "deleteLegacy")
        #expect(store.legacy == .value(secret))
        #expect(store.protected == .value(secret))
    }

    @Test func aProtectedItemThatDiffersFromTheLegacyItemIsLeftAlone() {
        let store = RecordingCredentialKeychain(legacy: .value(secret), protected: .value(Data("already-stored".utf8)))
        let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .needsReentry)
        #expect(store.kinds == ["readLegacy", "readProtected"])
        #expect(store.writes.isEmpty)
        #expect(store.legacy == .value(secret))
        #expect(store.protected == .value(Data("already-stored".utf8)))
    }

    @Test func anUnreadableLegacyItemIsNotDeletedAndIsNotAReentry() {
        let store = RecordingCredentialKeychain(legacy: .unreadable)
        let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .locked)
        #expect(outcome.state == .locked)
        #expect(outcome.state.title == "Unlock this Mac to use this key")
        #expect(store.kinds == ["readLegacy", "readProtected"])
        #expect(store.writes.isEmpty)
    }

    @Test func nothingOnThisMacStaysMissingRatherThanReentry() {
        let store = RecordingCredentialKeychain()
        let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .absent)
        #expect(outcome.state == .missing)
        #expect(outcome.state.detail.contains("does not move"))
        #expect(store.kinds == ["readLegacy", "readProtected"])
    }

    @Test func aFreshSaveWritesThenReadsBackThenDeletesTheLegacyItem() throws {
        let store = RecordingCredentialKeychain(legacy: .value(Data("old-copy".utf8)))
        let outcome = CredentialKeychainMigration.write(data: secret, service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .migrated)
        #expect(store.kinds == ["writeProtected", "readProtected", "deleteLegacy"])
        let write = try #require(store.writes.first)
        #expect(write.useDataProtectionKeychain)
        #expect(write.accessibility == .whenUnlockedThisDeviceOnly)
        #expect(store.legacy == .absent)
        #expect(store.protected == .value(secret))
        #expect(!store.log.contains("synthetic-key-value"))
        #expect(!store.log.contains("old-copy"))
    }

    @Test func aFreshSaveThatDoesNotReadBackLeavesTheLegacyItem() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.corruptReadBack = true
        let outcome = CredentialKeychainMigration.write(data: secret, service: service, account: account, teamIdentifier: team, keychain: store)
        #expect(outcome == .needsReentry)
        #expect(outcome.state.title == KeychainSecretState.needsReentry.title)
        #expect(store.kinds == ["writeProtected", "readProtected"])
        #expect(store.legacy == .value(secret))
    }

    private func secretComesAfterTheVerifyingRead(_ kinds: [String]) -> Bool {
        guard let write = kinds.firstIndex(of: "writeProtected"),
              let delete = kinds.firstIndex(of: "deleteLegacy") else { return false }
        let between = kinds[write..<delete]
        return between.contains("readProtected") && write < delete
    }

    @Test func aForeignLegacyItemIsNotImported() {
        let planted = [
            LegacyItemFacts(label: "other", creator: "SECU", anyProgram: true),
            LegacyItemFacts(label: "other", creator: "SECU", anyProgram: false),
            LegacyItemFacts(label: "ZEUS", creator: "ZEUS", anyProgram: true),
        ]
        for facts in planted {
            #expect(!CredentialKeychainPolicy.zeusWrote(facts))
            let store = RecordingCredentialKeychain(legacy: .value(secret))
            store.facts = facts
            let result = CredentialKeychainMigration.migrateOnce(
                service: service, account: account, teamIdentifier: team, keychain: store, alreadyMigrated: false)
            #expect(result.markMigrated)
            #expect(result.outcome != .migrated)
            #expect(store.writes.isEmpty)
            #expect(!store.kinds.contains("deleteLegacy"))
            #expect(store.protected == .absent)
            #expect(store.legacy == .value(secret))
        }
        #expect(CredentialKeychainPolicy.zeusWrote(.zeus))
    }

    @Test func theCliSwitchStaysOffAfterOff() {
        let on = Data("1".utf8)
        let store = RecordingCredentialKeychain(legacy: .value(on), protected: .value(on))
        store.facts = .zeus
        store.protected = .absent
        let first = CredentialKeychainMigration.migrateOnce(
            service: service, account: CredentialKeychainPolicy.cliSwitchAccount,
            teamIdentifier: team, keychain: store, alreadyMigrated: false)
        #expect(first.markMigrated)
        #expect(store.writes.isEmpty)
        #expect(store.protected == .absent)
        #expect(!store.kinds.contains("readLegacy"))
        #expect(!store.kinds.contains("writeProtected"))
        let second = CredentialKeychainMigration.migrateOnce(
            service: service, account: CredentialKeychainPolicy.cliSwitchAccount,
            teamIdentifier: team, keychain: store, alreadyMigrated: true)
        #expect(store.writes.isEmpty)
        #expect(store.protected == .absent)
        #expect(store.legacy == .value(on))
    }

    @Test func migrationRunsOnce() {
        let name = NSTemporaryDirectory() + "zeus.dp.flag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let flags = MigrationFlagStore(defaults: defaults)
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.facts = LegacyItemFacts(label: "ZEUS", creator: "ZEUS", anyProgram: false,
                                       trustedRequirements: [CredentialKeychainPolicy.designatedRequirement(teamIdentifier: team)!])
        let saved = "elevenlabs.api-key"
        #expect(!flags.contains(service: service, account: saved))
        let first = CredentialKeychainMigration.migrateOnce(
            service: service, account: saved, teamIdentifier: team, keychain: store,
            alreadyMigrated: flags.contains(service: service, account: saved))
        #expect(first.outcome == .migrated)
        #expect(first.markMigrated)
        if first.markMigrated { flags.mark(service: service, account: saved) }
        store.legacy = .value(Data("planted-later".utf8))
        let reloaded = MigrationFlagStore(defaults: defaults)
        #expect(reloaded.contains(service: service, account: saved))
        let mark = store.kinds.count
        _ = CredentialKeychainMigration.migrateOnce(
            service: service, account: saved, teamIdentifier: team, keychain: store,
            alreadyMigrated: reloaded.contains(service: service, account: saved))
        let added = Array(store.kinds.dropFirst(mark))
        #expect(!added.contains("readLegacy"))
        #expect(!added.contains("writeProtected"))
        #expect(store.writes.count == 1)
        #expect(store.protected == .value(secret))
    }

    @Test func aMissingGroupDoesNotImportOrRecordTheFlag() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.facts = .zeus
        let result = CredentialKeychainMigration.migrateOnce(
            service: service, account: account, teamIdentifier: "", keychain: store, alreadyMigrated: false)
        #expect(result.outcome == .needsReentry)
        #expect(!result.markMigrated)
        #expect(store.kinds.isEmpty)
        #expect(store.legacy == .value(secret))
        #expect(store.protected == .absent)
    }

    @Test func anAttackerOnlyAclIsNotImported() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.facts = LegacyItemFacts(label: "ZEUS", creator: "ZEUS", anyProgram: false,
                                       trustedRequirements: [Self.attackerRequirement])
        let result = CredentialKeychainMigration.migrateOnce(
            service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store, alreadyMigrated: false)
        #expect(!CredentialKeychainPolicy.aclIsOnlyZeus(store.facts, teamIdentifier: team))
        #expect(result.outcome != .migrated)
        #expect(store.writes.isEmpty)
        #expect(!store.kinds.contains("deleteLegacy"))
        #expect(store.legacy == .value(secret))
        #expect(store.protected == .absent)
    }

    @Test func aPlantedProviderKeyAndAnOriginAccountAreNotImported() {
        let zeusOnly = LegacyItemFacts(label: "ZEUS", creator: "ZEUS", anyProgram: false,
                                        trustedRequirements: [CredentialKeychainPolicy.designatedRequirement(teamIdentifier: team)!])
        for name in ["planted.provider.key", "anyllm-api-key.origin", "license.server.origin"] {
            let store = RecordingCredentialKeychain(legacy: .value(secret))
            store.facts = zeusOnly
            let result = CredentialKeychainMigration.migrateOnce(
                service: service, account: name, teamIdentifier: team, keychain: store, alreadyMigrated: false)
            #expect(result.outcome != .migrated)
            #expect(store.writes.isEmpty)
            #expect(!store.kinds.contains("deleteLegacy"))
            #expect(store.legacy == .value(secret))
        }
    }

    @Test func aSecondLegacyItemWithDifferentBytesIsKept() {
        let other = Data("other-legacy-value".utf8)
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.facts = LegacyItemFacts(label: "ZEUS", creator: "ZEUS", anyProgram: false,
                                       trustedRequirements: [CredentialKeychainPolicy.designatedRequirement(teamIdentifier: team)!])
        store.sibling = other
        _ = CredentialKeychainMigration.migrateOnce(
            service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store, alreadyMigrated: false)
        #expect(store.sibling == other)
        #expect(store.protected == .value(secret))
    }

    @Test func aRerunAfterTheFlagIsClearedDoesNotImportAnAttackerOrDropTheOtherItem() {
        let store = RecordingCredentialKeychain(legacy: .value(secret))
        store.facts = LegacyItemFacts(label: "ZEUS", creator: "ZEUS", anyProgram: false,
                                       trustedRequirements: [CredentialKeychainPolicy.designatedRequirement(teamIdentifier: team)!])
        let other = Data("other-legacy-value".utf8)
        store.sibling = other
        let first = CredentialKeychainMigration.migrateOnce(
            service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store, alreadyMigrated: false)
        #expect(first.outcome == .migrated)
        store.legacy = .value(Data("planted-later".utf8))
        store.facts = LegacyItemFacts(label: "ZEUS", creator: "ZEUS", anyProgram: false,
                                       trustedRequirements: [Self.attackerRequirement])
        let second = CredentialKeychainMigration.migrateOnce(
            service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store, alreadyMigrated: false)
        #expect(second.outcome != .migrated)
        #expect(store.protected == .value(secret))
        #expect(store.legacy == .value(Data("planted-later".utf8)))
        #expect(store.sibling == other)
    }

    @Test func migrationDoesNotPrintTheSecret() {
        let unique = Data("synthetic-key-value".utf8)
        let store = RecordingCredentialKeychain(legacy: .value(unique))
        store.facts = LegacyItemFacts(label: "ZEUS", creator: "ZEUS", anyProgram: false,
                                       trustedRequirements: [CredentialKeychainPolicy.designatedRequirement(teamIdentifier: team)!])
        let output = capturedOutput {
            _ = CredentialKeychainMigration.migrate(service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store)
            _ = CredentialKeychainMigration.migrateOnce(service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store, alreadyMigrated: false)
            _ = CredentialKeychainMigration.write(data: unique, service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store)
            _ = CredentialKeychainMigration.removeKeepingLegacy(service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store)
        }
        #expect(!output.contains(unique))
        #expect(!store.log.contains("synthetic-key-value"))
        #expect(!CredentialKeychainMigration.logLine(account: "elevenlabs.api-key", outcome: .migrated).contains("synthetic-key-value"))
    }

    @Test func turningOffCopiesTheKeyBackBeforeDroppingTheProtectedItem() {
        let store = RecordingCredentialKeychain(protected: .value(secret))
        let other = Data("other-legacy-value".utf8)
        store.sibling = other
        let result = CredentialKeychainMigration.removeKeepingLegacy(
            service: service, account: "elevenlabs.api-key", teamIdentifier: team, keychain: store)
        #expect(result.outcome == .migrated || result.outcome == .alreadyProtected)
        #expect(store.protected == .absent)
        #expect(store.legacy == .value(secret))
        #expect(store.sibling == other)
    }

    private static let attackerRequirement = "identifier \"com.attacker.tool\" and certificate leaf[subject.OU] = \"ATKTEAM01\""

    private func capturedOutput(_ body: () -> Void) -> Data {
        flushStandardStreams()
        let outPipe = Pipe()
        let errPipe = Pipe()
        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        dup2(outPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        body()
        flushStandardStreams()
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        close(savedOut)
        close(savedErr)
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        return outPipe.fileHandleForReading.readDataToEndOfFile() + errPipe.fileHandleForReading.readDataToEndOfFile()
    }

    /// Flushes C stdio without naming the imported `stdout` or `stderr` variables.
    private func flushStandardStreams() {
        guard let handle = dlopen(nil, RTLD_NOW) else { return }
        defer { dlclose(handle) }
        for name in ["_IO_2_1_stdout_", "_IO_2_1_stderr_", "__stdoutp", "__stderrp"] {
            guard let symbol = dlsym(handle, name) else { continue }
            let file = UnsafeMutablePointer<FILE>(OpaquePointer(symbol))
            fflush(file)
        }
    }
}
