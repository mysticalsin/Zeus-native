import Foundation
import Testing
@testable import ZeusCore

/// S03-08. Face templates are a data-protection keychain item. The OS protection is requested on
/// save and on read. These tests use an injected keychain, so nothing here touches the login keychain.
@Suite("Face template access")
struct FaceTemplateAccessTests {
    private let secret = Data("TEMPLATE-BYTES-SECRET".utf8)
    private let identity = "face-owner-7"

    private func memory() -> MemoryFaceTemplateKeychain { MemoryFaceTemplateKeychain() }

    private func store(_ keychain: MemoryFaceTemplateKeychain,
                       protection: FaceTemplateProtection = .biometryCurrentSetOrDevicePasscode,
                       lines: LockedLines? = nil) -> FaceTemplateStore {
        FaceTemplateStore(keychain: keychain, account: "face.presence.templates", protection: protection,
                          log: { lines?.add($0) })
    }

    @Test func saveAndReadRequireTheSamePresenceProtection() {
        let keychain = memory()
        let store = store(keychain)
        #expect(store.save(secret, identity: identity) == .success(()))
        let item = keychain.item(account: "face.presence.templates")
        #expect(item?.protection == .biometryCurrentSetOrDevicePasscode)
        #expect(FaceTemplateAccessControl.flags(for: .biometryCurrentSetOrDevicePasscode)
            == ["WhenUnlockedThisDeviceOnly", "biometryCurrentSet", "devicePasscode"])
        var seen = Data()
        #expect(store.withTemplate(identity: identity) { seen = $0 } == .success(()))
        #expect(seen == secret)
        #expect(keychain.reads == 1)
        #expect(keychain.writes == 1)
    }

    @Test func userPresenceAndBiometryCurrentSetAreBothRefusedWithoutThatProtection() {
        let keychain = memory()
        keychain.plantUnprotected(account: "face.presence.templates", payload: secret)
        let userPresence = store(keychain, protection: .userPresence)
        let biometry = store(keychain, protection: .biometryCurrentSetOrDevicePasscode)
        #expect(userPresence.withTemplate(identity: identity) { _ in } == .failure(.unavailable))
        #expect(biometry.withTemplate(identity: identity) { _ in } == .failure(.unavailable))
        #expect(FaceTemplateAccessControl.flags(for: .userPresence) == ["WhenUnlockedThisDeviceOnly", "userPresence"])

        #expect(userPresence.save(secret, identity: identity) == .success(()))
        #expect(biometry.withTemplate(identity: identity) { _ in } == .failure(.unavailable))
        #expect(userPresence.withTemplate(identity: identity) { _ in } == .success(()))

        let other = memory()
        #expect(store(other).save(secret, identity: identity) == .success(()))
        #expect(store(other, protection: .userPresence).withTemplate(identity: identity) { _ in } == .failure(.unavailable))
    }

    @Test func cancelledOrFailedSaveStoresNothing() {
        for failure in [FaceTemplateFailure.cancelled, .unavailable] {
            let keychain = memory()
            keychain.failWrites = failure
            let store = store(keychain)
            #expect(store.save(secret, identity: identity) == .failure(failure))
            #expect(keychain.item(account: "face.presence.templates") == nil)
            #expect(store.cachedPayload == nil)
            var called = false
            #expect(store.withTemplate(identity: identity) { _ in called = true } == .failure(.missing))
            #expect(!called)
        }
    }

    @Test func cancelledReadFailsClosedAndSkipsTheMatch() {
        let keychain = memory()
        let store = store(keychain)
        #expect(store.save(secret, identity: identity) == .success(()))
        keychain.failReads = .cancelled
        var called = false
        #expect(store.withTemplate(identity: identity) { _ in called = true } == .failure(.cancelled))
        #expect(!called)
        #expect(store.cachedPayload == nil)
        // The protected item is still there. A cancelled prompt does not wipe it and does not fall open.
        #expect(keychain.item(account: "face.presence.templates")?.payload == secret)
    }

    @Test func aMatchIsNotCachedAndTheNextMatchReadsAgain() {
        let keychain = memory()
        let store = store(keychain)
        #expect(store.save(secret, identity: identity) == .success(()))
        var first = Data()
        #expect(store.withTemplate(identity: identity) { first = $0 } == .success(()))
        #expect(first == secret)
        #expect(store.cachedPayload == nil)
        var second = Data()
        #expect(store.withTemplate(identity: identity) { second = $0 } == .success(()))
        #expect(second == secret)
        #expect(keychain.reads == 2)
        #expect(store.cachedPayload == nil)
    }

    @Test func biometryChangeReturnsNoTemplate() {
        let keychain = memory()
        let store = store(keychain)
        #expect(store.save(secret, identity: identity) == .success(()))
        keychain.failReads = .biometryChanged
        var called = false
        #expect(store.withTemplate(identity: identity) { _ in called = true } == .failure(.biometryChanged))
        #expect(!called)
        #expect(store.cachedPayload == nil)
        #expect(keychain.item(account: "face.presence.templates") == nil)
        keychain.failReads = nil
        #expect(store.withTemplate(identity: identity) { _ in } == .failure(.missing))
    }

    @Test func migrationDeletesTheOldCopyOnlyAfterTheNewCopyMatches() {
        let old = LockedData(secret)
        let written = LockedData(nil)
        var deletedOld = false
        var deletedNew = false
        let result = FaceTemplateMigration.run(
            readOld: { .success(old.value ?? Data()) },
            writeNew: { written.value = $0; return .success(()) },
            readNew: { .success(written.value ?? Data()) },
            deleteNew: { deletedNew = true; written.value = nil; return .success(()) },
            deleteOld: { deletedOld = true; return .success(()) })
        #expect(result == .success(()))
        #expect(deletedOld)
        #expect(!deletedNew)
        #expect(written.value == secret)
    }

    @Test func migrationKeepsTheOldCopyWhenVerificationFails() {
        let old = LockedData(secret)
        var deletedOld = false
        var deletedNew = false
        let result = FaceTemplateMigration.run(
            readOld: { .success(old.value ?? Data()) },
            writeNew: { _ in .success(()) },
            readNew: { .success(Data("other-template".utf8)) },
            deleteNew: { deletedNew = true; return .success(()) },
            deleteOld: { deletedOld = true; return .success(()) })
        #expect(result == .failure(.notVerified))
        #expect(!deletedOld)
        #expect(deletedNew)
        #expect(old.value == secret)
    }

    @Test func migrationKeepsTheOldCopyWhenTheWriteOrReadIsCancelled() {
        for failure in [FaceTemplateFailure.cancelled, .unavailable] {
            var deletedOld = false
            var wrote = false
            let writeCancelled = FaceTemplateMigration.run(
                readOld: { .success(secret) },
                writeNew: { _ in wrote = true; return .failure(failure) },
                readNew: { Issue.record("read after a failed write"); return .success(secret) },
                deleteNew: { .success(()) },
                deleteOld: { deletedOld = true; return .success(()) })
            #expect(writeCancelled == .failure(failure))
            #expect(wrote)
            #expect(!deletedOld)

            deletedOld = false
            var deletedNew = false
            let readCancelled = FaceTemplateMigration.run(
                readOld: { .success(secret) },
                writeNew: { _ in .success(()) },
                readNew: { .failure(failure) },
                deleteNew: { deletedNew = true; return .success(()) },
                deleteOld: { deletedOld = true; return .success(()) })
            #expect(readCancelled == .failure(failure))
            #expect(deletedNew)
            #expect(!deletedOld)
        }
    }

    @Test func logsNeverIncludeTemplateBytesOrASizeTiedToAnIdentity() {
        let lines = LockedLines()
        let keychain = memory()
        let store = store(keychain, lines: lines)
        #expect(store.save(secret, identity: identity) == .success(()))
        #expect(store.withTemplate(identity: identity) { _ in } == .success(()))
        #expect(lines.values.contains(FaceTemplateLog.line("save")))
        #expect(lines.values.contains(FaceTemplateLog.line("read")))
        for line in lines.values {
            #expect(!FaceTemplateLog.exposesPrivateMaterial(line, identity: identity, payload: secret))
        }
        let leaked = "\(identity) \(secret.count)"
        #expect(FaceTemplateLog.exposesPrivateMaterial(leaked, identity: identity, payload: secret))
        #expect(FaceTemplateLog.exposesPrivateMaterial("TEMPLATE-BYTES-SECRET", identity: identity, payload: secret))
    }

    @Test func wordingMatchesTouchIDPasscodeAndReenrol() {
        #expect(FaceTemplateCopy.enroll == "Saving a face asks for Touch ID or the device passcode. Zeus does not keep the face print after it checks a match.")
        #expect(FaceTemplateCopy.reenrol == "Fingerprints on this Mac changed. Enroll this face again.")
        #expect(FaceTemplateCopy.enroll.contains("Touch ID"))
        #expect(FaceTemplateCopy.enroll.contains("device passcode"))
        #expect(FaceTemplateCopy.reenrol.contains("Enroll"))
    }

    @Test func saveAddsANewTemplateWithoutDeletingFirst() {
        let items = ScriptedFaceTemplateItems()
        let record = FaceTemplateRecord(account: "face.presence.templates",
                                        protection: .biometryCurrentSetOrDevicePasscode, payload: secret)
        #expect(FaceTemplateSecureSession.write(record, items: items) == .success(()))
        #expect(items.operations == ["add"])
        #expect(items.payload(account: record.account) == secret)
    }

    @Test func failedReplaceKeepsTheStoredTemplate() {
        let items = ScriptedFaceTemplateItems()
        let record = FaceTemplateRecord(account: "face.presence.templates",
                                        protection: .biometryCurrentSetOrDevicePasscode, payload: secret)
        #expect(FaceTemplateSecureSession.write(record, items: items) == .success(()))
        items.failReplace = .unavailable
        let next = FaceTemplateRecord(account: record.account, protection: record.protection, payload: Data("other-template".utf8))
        #expect(FaceTemplateSecureSession.write(next, items: items) == .failure(.unavailable))
        #expect(items.payload(account: record.account) == secret)
        #expect(items.operations == ["add", "replace"])
    }

    @Test func readPresentsTheItemsAccessControl() {
        let items = ScriptedFaceTemplateItems()
        let record = FaceTemplateRecord(account: "face.presence.templates",
                                        protection: .biometryCurrentSetOrDevicePasscode, payload: secret)
        #expect(FaceTemplateSecureSession.write(record, items: items) == .success(()))
        #expect(FaceTemplateSecureSession.read(account: record.account, requiring: record.protection, items: items) == .success(secret))
        #expect(items.lastAuthentication?.presentsAccessControl == true)
        #expect(items.lastAuthentication?.protection == .biometryCurrentSetOrDevicePasscode)
        #expect(items.lastAuthentication?.operationPrompt == "Authenticate with Touch ID or the device passcode to read the face template.")
    }

    @Test func unprotectedTemplateIsNotReturned() {
        let items = ScriptedFaceTemplateItems()
        items.plantUnprotected(account: "face.presence.templates", payload: secret)
        #expect(FaceTemplateSecureSession.read(account: "face.presence.templates",
                                               requiring: .biometryCurrentSetOrDevicePasscode,
                                               items: items) == .failure(.unavailable))
        #expect(items.payload(account: "face.presence.templates") == secret)
    }

    @Test func evaluationFailureDeniesTheFaceTemplate() {
        let stored = Data("epoch-a".utf8)
        #expect(FaceTemplateDomainGate.denies(stored: stored, evaluation: .failed))
        #expect(FaceTemplateDomainGate.denies(stored: nil, evaluation: .failed))
    }

    @Test func nilDomainStateDeniesTheFaceTemplate() {
        #expect(FaceTemplateDomainGate.denies(stored: Data("epoch-a".utf8), evaluation: .succeeded(nil)))
        #expect(FaceTemplateDomainGate.denies(stored: nil, evaluation: .succeeded(nil)))
        #expect(FaceTemplateDomainGate.denies(stored: Data(), evaluation: .succeeded(nil)))
    }

    @Test func changedDomainStateDeniesTheFaceTemplate() {
        let stored = Data("epoch-a".utf8)
        let changed = Data("epoch-b".utf8)
        #expect(FaceTemplateDomainGate.denies(stored: stored, evaluation: .succeeded(changed)))
        #expect(!FaceTemplateDomainGate.denies(stored: stored, evaluation: .succeeded(stored)))
        #expect(!FaceTemplateDomainGate.denies(stored: nil, evaluation: .succeeded(stored)))
    }

    @Test func failedEpochAddKeepsThePreviousRecord() {
        let existing = Data("epoch-a".utf8)
        let next = Data("epoch-b".utf8)
        #expect(FaceTemplateEpochWrite.plan(existing: existing) == .update)
        let kept = FaceTemplateEpochWrite.kept(existing: existing, next: next, succeeded: false)
        #expect(kept == existing)
        #expect(FaceTemplateDomainGate.denies(stored: kept, evaluation: .succeeded(next), enrolled: true))
        #expect(FaceTemplateDomainGate.denies(stored: nil, evaluation: .succeeded(next), enrolled: true))
        #expect(FaceTemplateEpochWrite.kept(existing: nil, next: next, succeeded: false) == nil)
        #expect(FaceTemplateEpochWrite.plan(existing: nil) == .add)
    }

    @Test func faceTemplateQueryUsesTheSharedAccessGroup() {
        let team = "TEAMID1234"
        let group = CredentialKeychainPolicy.accessGroup(teamIdentifier: team)
        #expect(group == team + "." + CredentialKeychainPolicy.accessGroupSuffix)
        let query = FaceTemplateKeychainAttributes.query(account: "face.presence.templates", teamIdentifier: team)
        #expect(query?["accessGroup"] == group)
        #expect(query?["service"] == "com.zeus.app")
        #expect(FaceTemplateKeychainAttributes.query(account: "face.presence.templates", teamIdentifier: "") == nil)
        #expect(FaceTemplateKeychainAttributes.query(account: "face.presence.templates", teamIdentifier: "team") == nil)
    }

    @Test func promptsMatchUserPresenceOrBiometryCurrentSetAndDevicePasscode() {
        let user = FaceTemplateSecureSession.authentication(for: .userPresence)
        let biometry = FaceTemplateSecureSession.authentication(for: .biometryCurrentSetOrDevicePasscode)
        #expect(user.protection == .userPresence)
        #expect(user.presentsAccessControl)
        #expect(user.operationPrompt == "Authenticate to read the face template.")
        #expect(FaceTemplateAccessControl.flags(for: .userPresence) == ["WhenUnlockedThisDeviceOnly", "userPresence"])
        #expect(biometry.protection == .biometryCurrentSetOrDevicePasscode)
        #expect(biometry.presentsAccessControl)
        #expect(biometry.operationPrompt == "Authenticate with Touch ID or the device passcode to read the face template.")
        #expect(FaceTemplateAccessControl.flags(for: .biometryCurrentSetOrDevicePasscode)
            == ["WhenUnlockedThisDeviceOnly", "biometryCurrentSet", "devicePasscode"])
    }
}

private final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    init(_ value: Data?) { stored = value }
    var value: Data? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Records secure-item calls. A read that does not present access control returns the bytes,
/// which is the system read this suite is replacing.
private final class ScriptedFaceTemplateItems: FaceTemplateSecureItems, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: FaceTemplateRecord] = [:]
    private var unprotected: [String: Data] = [:]
    var failReplace: FaceTemplateFailure?
    private(set) var operations: [String] = []
    private(set) var lastAuthentication: FaceTemplateAuthentication?

    func plantUnprotected(account: String, payload: Data) {
        lock.lock(); defer { lock.unlock() }
        unprotected[account] = payload
        records[account] = nil
    }

    func payload(account: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return records[account]?.payload ?? unprotected[account]
    }

    func probe(account: String) -> FaceTemplateProbe {
        lock.lock(); defer { lock.unlock() }
        if let data = unprotected[account] { return .unprotected(data) }
        if records[account] != nil { return .protected }
        return .missing
    }

    func add(_ record: FaceTemplateRecord, authentication: FaceTemplateAuthentication) -> Result<Void, FaceTemplateFailure> {
        lock.lock(); defer { lock.unlock() }
        operations.append("add")
        lastAuthentication = authentication
        if records[record.account] != nil || unprotected[record.account] != nil { return .failure(.unavailable) }
        records[record.account] = record
        return .success(())
    }

    func replace(_ record: FaceTemplateRecord, authentication: FaceTemplateAuthentication) -> Result<Void, FaceTemplateFailure> {
        lock.lock(); defer { lock.unlock() }
        operations.append("replace")
        lastAuthentication = authentication
        guard records[record.account] != nil || unprotected[record.account] != nil else { return .failure(.missing) }
        if let failReplace { return .failure(failReplace) }
        records[record.account] = record
        unprotected[record.account] = nil
        return .success(())
    }

    func read(account: String, authentication: FaceTemplateAuthentication) -> Result<Data, FaceTemplateFailure> {
        lock.lock(); defer { lock.unlock() }
        lastAuthentication = authentication
        if !authentication.presentsAccessControl || authentication.operationPrompt.isEmpty {
            if let record = records[account] { return .success(record.payload) }
            if let data = unprotected[account] { return .success(data) }
            return .failure(.missing)
        }
        if unprotected[account] != nil { return .failure(.unavailable) }
        guard let record = records[account] else { return .failure(.missing) }
        guard record.protection == authentication.protection else { return .failure(.unavailable) }
        return .success(record.payload)
    }

    func delete(account: String) -> Result<Void, FaceTemplateFailure> {
        lock.lock(); defer { lock.unlock() }
        operations.append("delete")
        records[account] = nil
        unprotected[account] = nil
        return .success(())
    }
}
