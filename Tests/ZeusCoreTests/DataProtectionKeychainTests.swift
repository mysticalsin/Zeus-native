import Foundation
import Testing
@testable import ZeusCore

/// Records Keychain attributes and the order of calls. Holds no file and calls no Keychain API.
private final class RecordingCredentialKeychain: CredentialKeychain, @unchecked Sendable {
    var legacy: KeychainRead
    var protected: KeychainRead
    var failWrite = false
    var failDelete = false
    var corruptReadBack = false
    var facts: LegacyItemFacts = .zeus
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
        store.facts = .zeus
        #expect(!flags.contains(service: service, account: account))
        let first = CredentialKeychainMigration.migrateOnce(
            service: service, account: account, teamIdentifier: team, keychain: store,
            alreadyMigrated: flags.contains(service: service, account: account))
        #expect(first.outcome == .migrated)
        #expect(first.markMigrated)
        if first.markMigrated { flags.mark(service: service, account: account) }
        store.legacy = .value(Data("planted-later".utf8))
        let reloaded = MigrationFlagStore(defaults: defaults)
        #expect(reloaded.contains(service: service, account: account))
        let mark = store.kinds.count
        _ = CredentialKeychainMigration.migrateOnce(
            service: service, account: account, teamIdentifier: team, keychain: store,
            alreadyMigrated: reloaded.contains(service: service, account: account))
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
}
