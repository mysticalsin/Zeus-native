import Foundation
import Testing
@testable import ZeusCore

/// The key and the activation proof commit together. A refusal is kept beside the key.
/// In-memory writes only. No Keychain, network or signed license.
@Suite struct LicenseCredentialCommitTests {
    private final class Store {
        var items: [String: String]
        var failWrites: Set<String> = []
        var failDeletes: Set<String> = []
        var writesLeft: [String: Int] = [:]

        init(items: [String: String] = [:]) { self.items = items }

        func write(_ value: String, _ account: String) -> Bool {
            if failWrites.contains(account) { return false }
            if let left = writesLeft[account] {
                guard left > 0 else { return false }
                writesLeft[account] = left - 1
            }
            items[account] = value
            return true
        }

        func delete(_ account: String) -> Bool {
            if failDeletes.contains(account) { return false }
            items[account] = nil
            return true
        }
    }

    @Test func aFailedProofWriteDoesNotSaveTheKey() {
        let store = Store()
        store.failWrites = [LicenseCredentialCommit.proofAccount]
        let result = LicenseCredentialCommit.store(key: "new-key", proof: "new-proof", previousProof: nil,
                                                   write: store.write, delete: store.delete)
        #expect(result == .proofNotSaved)
        #expect(store.items[LicenseCredentialCommit.keyAccount] == nil)
        #expect(store.items[LicenseCredentialCommit.proofAccount] == nil)
    }

    @Test func aFailedKeyWriteRestoresThePreviousProof() {
        let store = Store(items: [
            LicenseCredentialCommit.keyAccount: "old-key",
            LicenseCredentialCommit.proofAccount: "old-proof",
        ])
        store.failWrites = [LicenseCredentialCommit.keyAccount]
        let result = LicenseCredentialCommit.store(key: "new-key", proof: "new-proof", previousProof: "old-proof",
                                                   write: store.write, delete: store.delete)
        #expect(result == .keyNotSaved)
        #expect(store.items[LicenseCredentialCommit.proofAccount] == "old-proof")
        #expect(store.items[LicenseCredentialCommit.keyAccount] == "old-key")
        #expect(store.items[LicenseCredentialCommit.refusalAccount] == nil)
    }

    @Test func aFailedOfflineKeyWriteLeavesTheExistingProof() {
        let store = Store(items: [LicenseCredentialCommit.proofAccount: "old-proof"])
        store.failWrites = [LicenseCredentialCommit.keyAccount]
        let result = LicenseCredentialCommit.store(key: "new-key", proof: nil, previousProof: "old-proof",
                                                   write: store.write, delete: store.delete)
        #expect(result == .keyNotSaved)
        #expect(store.items[LicenseCredentialCommit.proofAccount] == "old-proof")
        #expect(store.items[LicenseCredentialCommit.keyAccount] == nil)
    }

    @Test func aFailedKeyWriteRemovesAProofThatHadNoPredecessor() {
        let store = Store()
        store.failWrites = [LicenseCredentialCommit.keyAccount]
        let result = LicenseCredentialCommit.store(key: "new-key", proof: "new-proof", previousProof: nil,
                                                   write: store.write, delete: store.delete)
        #expect(result == .keyNotSaved)
        #expect(store.items[LicenseCredentialCommit.proofAccount] == nil)
        #expect(store.items[LicenseCredentialCommit.keyAccount] == nil)
    }

    @Test func aFailedRollbackBlocksWhateverKeyRemains() {
        let store = Store(items: [
            LicenseCredentialCommit.keyAccount: "old-key",
            LicenseCredentialCommit.proofAccount: "old-proof",
        ])
        store.failWrites = [LicenseCredentialCommit.keyAccount]
        store.writesLeft[LicenseCredentialCommit.proofAccount] = 1
        let result = LicenseCredentialCommit.store(key: "new-key", proof: "new-proof", previousProof: "old-proof",
                                                   write: store.write, delete: store.delete)
        #expect(result == .blocked)
        #expect(store.items[LicenseCredentialCommit.keyAccount] == "old-key")
        #expect(store.items[LicenseCredentialCommit.refusalAccount] == LicenseCredentialCommit.blockAll)
        #expect(LicenseCredentialCommit.covers(refusal: store.items[LicenseCredentialCommit.refusalAccount],
                                              licenseID: "L-1", hasKey: true))
    }

    @Test func aRefusalStaysWithTheKeyWhenDeletionFails() {
        let store = Store(items: [LicenseCredentialCommit.keyAccount: "kept-key"])
        store.failDeletes = [LicenseCredentialCommit.keyAccount]
        let refusal = LicenseCredentialCommit.refuse(licenseID: "L-1", write: store.write, deleteKey: {
            store.delete(LicenseCredentialCommit.keyAccount)
        })
        #expect(refusal.recorded)
        #expect(!refusal.keyRemoved)
        #expect(!refusal.needsCleanup)
        #expect(store.items[LicenseCredentialCommit.keyAccount] == "kept-key")
        #expect(store.items[LicenseCredentialCommit.refusalAccount] == "L-1")
        #expect(LicenseCredentialCommit.covers(refusal: "L-1", licenseID: "L-1", hasKey: true))
        #expect(!LicenseCredentialCommit.covers(refusal: "L-1", licenseID: "L-2", hasKey: true))
        #expect(!LicenseCredentialCommit.covers(refusal: "L-1", licenseID: "L-1", hasKey: false))
    }

    @Test func aRefusalThatCannotBeStoredNeedsCleanup() {
        let store = Store(items: [LicenseCredentialCommit.keyAccount: "kept-key"])
        store.failWrites = [LicenseCredentialCommit.refusalAccount]
        store.failDeletes = [LicenseCredentialCommit.keyAccount]
        let refusal = LicenseCredentialCommit.refuse(licenseID: "L-1", write: store.write, deleteKey: {
            store.delete(LicenseCredentialCommit.keyAccount)
        })
        #expect(!refusal.recorded)
        #expect(!refusal.keyRemoved)
        #expect(refusal.needsCleanup)
        #expect(!LicenseCredentialCommit.covers(refusal: nil, licenseID: "L-1", hasKey: true))
    }

    @Test func blockAllCoversAnyStoredKey() {
        #expect(LicenseCredentialCommit.covers(refusal: LicenseCredentialCommit.blockAll, licenseID: nil, hasKey: true))
        #expect(LicenseCredentialCommit.covers(refusal: LicenseCredentialCommit.blockAll, licenseID: "L-9", hasKey: true))
        #expect(!LicenseCredentialCommit.covers(refusal: LicenseCredentialCommit.blockAll, licenseID: "L-9", hasKey: false))
        #expect(!LicenseCredentialCommit.covers(refusal: "", licenseID: "L-1", hasKey: true))
        #expect(!LicenseCredentialCommit.covers(refusal: nil, licenseID: "L-1", hasKey: true))
    }
}
