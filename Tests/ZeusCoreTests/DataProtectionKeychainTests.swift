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
}
