import Foundation
import Testing
@testable import ZeusCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite struct ExplanationHistoryTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private func fresh(revision: Int = 0) throws -> ExplanationHistory {
        try .init(scene: .init(sessionID: UUID(), sceneID: UUID(), revision: revision), title: "A useful explanation", at: date)
    }
    private func object(_ id: String) -> ExplanationObject {
        .init(id: id, geometry: .init(kind: .label), text: id, accessibleDescription: "Label \(id)")
    }
    private func key(_ history: ExplanationHistory, turn: UUID, sequence: Int = 0) -> ExplanationHistory.ModelEventKey {
        .init(sessionID: history.canonicalScene.sessionID, turnID: turn, sceneID: history.canonicalScene.sceneID,
              sequence: sequence, baseRevision: history.revision, revision: history.revision + 1, beatID: "beat-\(sequence)")
    }
    private func changed(_ history: ExplanationHistory, id: String) throws -> ExplanationScene {
        try ExplanationSceneReducer.applyingOperations([.create(object(id))], to: history.canonicalScene,
                                                       resultingRevision: history.revision)
    }

    @Test func actualCuesShareReservedRevisionAndCancellationNeverCommitsFutureScene() throws {
        var history = try fresh()
        let turn = UUID()
        try history.beginTurn(turn, at: date)
        let key = key(history, turn: turn)
        let token = try history.stageModelEvent(key: key, cueCount: 3)
        let staged = history
        #expect(history.revision == 1)
        #expect(history.checkpoints.count == 2)
        #expect(throws: ExplanationHistory.HistoryError.notStarted) {
            try history.admitCue(admissionID: token, key: key, cueIndex: 0, scene: changed(history, id: "unplayed"), at: date)
        }
        #expect(history == staged)
        try history.startModelEvent(admissionID: token, key: key, at: date)
        #expect(history.revision == 2 && !history.canUndo)
        try history.admitCue(admissionID: token, key: key, cueIndex: 0, scene: changed(history, id: "first"), at: date)
        try history.admitCue(admissionID: token, key: key, cueIndex: 1, scene: changed(history, id: "second"), at: date)
        #expect(history.revision == 2)
        #expect(history.checkpoints.suffix(3).map(\.scene.revision) == [2, 2, 2])
        #expect(history.checkpoints.suffix(3).map(\.ordinal) == [2, 3, 4])
        let unplayed = try changed(history, id: "never-admitted")
        try history.cancelModelEvent(admissionID: token, key: key)
        let cancelled = history
        #expect(throws: ExplanationHistory.HistoryError.invalidAdmission) {
            try history.admitCue(admissionID: token, key: key, cueIndex: 2, scene: unplayed, at: date)
        }
        #expect(history == cancelled)
        #expect(history.canonicalScene.objects["never-admitted"] == nil)
        try history.undo(at: date)
        #expect(history.revision == 3 && history.canonicalScene.objects.isEmpty && !history.canUndo)
        try history.redo(at: date)
        #expect(history.revision == 4 && history.canonicalScene.objects.count == 2)
    }

    @Test func spokenOnlyBeatReservesRevisionAtActualStartWithoutAnUndoEntry() throws {
        var history = try fresh()
        let turn = UUID(); try history.beginTurn(turn, at: date)
        let key = key(history, turn: turn)
        let token = try history.stageModelEvent(key: key, cueCount: 0)
        #expect(history.revision == 1)
        #expect(throws: ExplanationHistory.HistoryError.notStarted) { try history.finishModelEvent(admissionID: token, key: key) }
        try history.startModelEvent(admissionID: token, key: key, at: date)
        #expect(history.revision == 2)
        #expect(history.checkpoints.last?.kind == .modelStart)
        #expect(!history.canUndo)
        #expect(throws: ExplanationHistory.HistoryError.alreadyStarted) {
            try history.startModelEvent(admissionID: token, key: key, at: date)
        }
        try history.finishModelEvent(admissionID: token, key: key)
        #expect(throws: ExplanationHistory.HistoryError.invalidAdmission) { try history.cancelModelEvent(admissionID: token, key: key) }
    }

    @Test func repeatedOrOutOfOrderCueAndWrongTokenCannotModifyCanonicalScene() throws {
        var history = try fresh(); let turn = UUID(); try history.beginTurn(turn, at: date)
        let key = key(history, turn: turn); let token = try history.stageModelEvent(key: key, cueCount: 2)
        try history.startModelEvent(admissionID: token, key: key, at: date)
        let scene = try changed(history, id: "a")
        let before = history
        #expect(throws: ExplanationHistory.HistoryError.invalidAdmission) {
            try history.admitCue(admissionID: UUID(), key: key, cueIndex: 0, scene: scene, at: date)
        }
        #expect(throws: ExplanationHistory.HistoryError.cueOutOfOrder) {
            try history.admitCue(admissionID: token, key: key, cueIndex: 1, scene: scene, at: date)
        }
        #expect(history == before)
        try history.admitCue(admissionID: token, key: key, cueIndex: 0, scene: scene, at: date)
        let after = history
        #expect(throws: ExplanationHistory.HistoryError.cueOutOfOrder) {
            try history.admitCue(admissionID: token, key: key, cueIndex: 0, scene: scene, at: date)
        }
        #expect(history == after)
    }

    @Test func userEditInvalidatesQueuedModelAndNewEditAfterUndoClearsRedo() throws {
        var history = try fresh(); let turn = UUID(); try history.beginTurn(turn, at: date)
        let key = key(history, turn: turn); let token = try history.stageModelEvent(key: key, cueCount: 1)
        try history.applyUserScene(changed(history, id: "manual"), baseRevision: history.revision, at: date)
        let manual = history
        #expect(throws: ExplanationHistory.HistoryError.invalidAdmission) {
            try history.startModelEvent(admissionID: token, key: key, at: date)
        }
        #expect(throws: ExplanationHistory.HistoryError.staleRevision) {
            try history.applyUserScene(manual.canonicalScene, baseRevision: 1, at: date)
        }
        #expect(history == manual)
        try history.undo(at: date)
        #expect(history.canRedo)
        try history.applyUserScene(changed(history, id: "replacement"), baseRevision: history.revision, at: date)
        #expect(!history.canRedo && history.canonicalScene.objects["manual"] == nil)
    }

    @Test func newTurnInvalidatesStartedPlaybackAndReplayIsReadOnly() throws {
        var history = try fresh(); let turn = UUID(); try history.beginTurn(turn, at: date)
        let key = key(history, turn: turn); let token = try history.stageModelEvent(key: key, cueCount: 1)
        try history.startModelEvent(admissionID: token, key: key, at: date)
        try history.admitCue(admissionID: token, key: key, cueIndex: 0, scene: changed(history, id: "a"), at: date)
        let old = history.checkpoints.first!
        try history.beginTurn(UUID(), at: date)
        #expect(history.revision == 3)
        let before = history
        let replay = try history.replay(checkpointID: old.id)
        #expect(replay.scene.objects.isEmpty)
        #expect(history == before && history.canonicalScene.objects.count == 1)
        #expect(throws: ExplanationHistory.HistoryError.invalidAdmission) { try history.finishModelEvent(admissionID: token, key: key) }
    }

    @Test func restartKeepsOnlyAppliedSnapshotsAndNeverRevivesAdmission() throws {
        var history = try fresh(); let turn = UUID(); try history.beginTurn(turn, at: date)
        try history.appendMessage(role: .user, text: "Explain this triangle", at: date)
        let key = key(history, turn: turn); let token = try history.stageModelEvent(key: key, cueCount: 2)
        try history.startModelEvent(admissionID: token, key: key, at: date)
        try history.admitCue(admissionID: token, key: key, cueIndex: 0, scene: changed(history, id: "triangle"), at: date)
        let data = try history.encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains(token.uuidString))
        #expect(!text.contains("admission"))
        var reopened = try ExplanationHistory.decoded(data)
        #expect(reopened.canonicalScene == history.canonicalScene)
        #expect(reopened.messages == history.messages && reopened.checkpoints == history.checkpoints)
        #expect(throws: ExplanationHistory.HistoryError.invalidAdmission) {
            try reopened.admitCue(admissionID: token, key: key, cueIndex: 1, scene: changed(reopened, id: "late"), at: date)
        }
        try reopened.undo(at: date)
        #expect(reopened.canonicalScene.objects.isEmpty && reopened.revision == 3)
    }

    @Test func interruptedAnimationUndoReturnsPreBeatSceneInsteadOfNeverShownFutureTarget() throws {
        var baseline = try fresh().canonicalScene
        baseline.objects["moving"] = object("moving")
        var history = try ExplanationHistory(scene: baseline, title: "Motion", at: date)
        let turn = UUID(); try history.beginTurn(turn, at: date)
        let key = key(history, turn: turn); let token = try history.stageModelEvent(key: key, cueCount: 1)
        try history.startModelEvent(admissionID: token, key: key, at: date)
        let target = try ExplanationSceneReducer.applyingOperations([
            .animate(id: "moving", animation: .init(property: .position, to: .init(x: 100, y: 0), duration: 2))
        ], to: history.canonicalScene, resultingRevision: history.revision)
        try history.admitCue(admissionID: token, key: key, cueIndex: 0, scene: target, at: date)
        var displayed = target
        displayed.objects["moving"]?.transform.position.x = 50
        try history.freezePlayback(scene: displayed, baseRevision: history.revision, at: date)
        #expect(history.revision == 3 && history.checkpoints.last?.kind == .interruption)
        #expect(history.canonicalScene.objects["moving"]?.transform.position.x == 50)
        #expect(throws: ExplanationHistory.HistoryError.invalidAdmission) { try history.finishModelEvent(admissionID: token, key: key) }
        try history.undo(at: date)
        #expect(history.revision == 4 && history.canonicalScene.objects["moving"]?.transform.position.x == 0)
        #expect(!history.canUndo)
        try history.redo(at: date)
        #expect(history.revision == 5 && history.canonicalScene.objects["moving"]?.transform.position.x == 50)
        #expect(try ExplanationHistory.decoded(history.encoded()) == history)
    }

    @Test func retentionCountersExposeDroppedConversationCheckpointsAndUndo() throws {
        var history = try fresh()
        for index in 0..<70 {
            try history.appendMessage(role: .user, text: "Message \(index)", at: date)
        }
        #expect(history.messages.count == 32 && history.discardedMessages == 38)
        #expect(history.checkpoints.count == 64 && history.discardedCheckpoints == 7)
        for index in 0..<18 {
            try history.applyUserScene(changed(history, id: "o\(index)"), baseRevision: history.revision, at: date)
        }
        #expect(history.discardedUndoStates == 2)
        #expect(try ExplanationHistory.decoded(history.encoded()) == history)
    }

    @Test func malformedVersionsIdentityDatesAndCheckpointOrderAreRejected() throws {
        let history = try fresh()
        let data = try history.encoded()
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["version"] = 99
        #expect(throws: ExplanationHistory.HistoryError.unsupportedVersion(99)) {
            try ExplanationHistory.decoded(JSONSerialization.data(withJSONObject: root))
        }
        root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var checkpoints = try #require(root["checkpoints"] as? [[String: Any]])
        checkpoints[0]["ordinal"] = -1; root["checkpoints"] = checkpoints
        #expect(throws: ExplanationHistory.HistoryError.invalidHistory) {
            try ExplanationHistory.decoded(JSONSerialization.data(withJSONObject: root))
        }
        var other = history.canonicalScene; other.sceneID = UUID()
        var editable = history
        #expect(throws: ExplanationHistory.HistoryError.wrongIdentity) {
            try editable.applyUserScene(other, baseRevision: history.revision, at: date)
        }
        #expect(throws: ExplanationHistory.HistoryError.invalidDate) {
            try editable.beginTurn(UUID(), at: date.addingTimeInterval(-1))
        }
        #expect(editable == history)
    }

    @Test func decodedCueOrderAndRevisionGapsCannotForgeAppliedHistory() throws {
        var history = try fresh(); let turn = UUID(); try history.beginTurn(turn, at: date)
        let key = key(history, turn: turn); let token = try history.stageModelEvent(key: key, cueCount: 2)
        try history.startModelEvent(admissionID: token, key: key, at: date)
        try history.admitCue(admissionID: token, key: key, cueIndex: 0, scene: changed(history, id: "one"), at: date)
        try history.admitCue(admissionID: token, key: key, cueIndex: 1, scene: changed(history, id: "two"), at: date)
        let data = try history.encoded()
        for field in ["cueIndex", "ordinal"] {
            var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var checkpoints = try #require(root["checkpoints"] as? [[String: Any]])
            checkpoints[checkpoints.count - 1][field] = field == "cueIndex" ? 0 : 99
            root["checkpoints"] = checkpoints
            #expect(throws: ExplanationHistory.HistoryError.invalidHistory) {
                try ExplanationHistory.decoded(JSONSerialization.data(withJSONObject: root))
            }
        }
    }

    @Test func revisionAndSizeLimitsRejectWithoutMutatingHistory() throws {
        var exhausted = try fresh(revision: ExplanationLimits.revision)
        let before = exhausted
        #expect(throws: ExplanationHistory.HistoryError.revisionExhausted) { try exhausted.beginTurn(UUID(), at: date) }
        #expect(exhausted == before)
        var history = try fresh()
        let original = history
        #expect(throws: ExplanationHistory.HistoryError.limitExceeded) {
            try history.appendMessage(role: .user, text: String(repeating: "x", count: 16_385), at: date)
        }
        #expect(history == original)
        #expect(throws: ExplanationHistory.HistoryError.limitExceeded) {
            try ExplanationHistory.decoded(Data(repeating: 0, count: ExplanationHistory.maxRecordBytes + 1))
        }
    }

    @Test func missingRegistryFailsRestoreWhileCaptureIDsRemainInertMetadata() throws {
        var scene = try fresh().canonicalScene
        scene.captureID = UUID()
        var label = object("reference"); label.sourceIDs = ["source-a"]
        scene.objects[label.id] = label
        let registry = ExplanationRegistry(sourceIDs: ["source-a"])
        let history = try ExplanationHistory(scene: scene, title: "Source explanation", at: date, registry: registry)
        let data = try history.encoded(registry: registry)
        #expect(throws: ExplanationFailure.self) { try ExplanationHistory.decoded(data) }
        #expect(try ExplanationHistory.decoded(data, registry: registry).canonicalScene.captureID == scene.captureID)
        #expect(throws: ExplanationFailure.self) { try history.replay(checkpointID: history.lastCheckpointID) }
    }

    private struct Scratch {
        let base: URL
        var root: URL { base.appendingPathComponent("history", isDirectory: true) }
        init() throws {
            let created = FileManager.default.temporaryDirectory
                .appendingPathComponent("zeus-explanation-test-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: created, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            // Resolve only this newly created, owned fixture. On Darwin, Foundation's
            // resolvingSymlinksInPath can retain the /var alias that the store correctly refuses.
            guard let resolved = realpath(created.path, nil) else {
                let failure = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                try? FileManager.default.removeItem(at: created)
                throw failure
            }
            defer { free(resolved) }
            base = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        }
        func remove() { try? FileManager.default.removeItem(at: base) }
        func file(_ history: ExplanationHistory) -> URL { root.appendingPathComponent(ExplanationHistoryStore.fileName(history.id)) }
        func store(policy: ExplanationHistoryStore.Policy = .init(),
                   fault: (@Sendable (ExplanationHistoryStore.FaultStage) throws -> Void)? = nil) throws -> ExplanationHistoryStore {
            try .init(root: root, policy: policy, faultHook: fault)
        }
        func names() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() }
    }
    private struct InjectedFailure: Error, Equatable {}

    @Test func scratchRootIsCanonicalAndHasNoSymlinkComponents() async throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let store = try scratch.store()
        let history = try fresh()
        _ = try await store.save(history, now: date)
        #expect(try await store.load(id: history.id) == history)
        let resolved = try #require(realpath(scratch.root.path, nil))
        defer { free(resolved) }
        #expect(scratch.root.path == String(cString: resolved))

        var folder = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        try #require(folder >= 0)
        defer { _ = close(folder) }
        for component in scratch.root.path.split(separator: "/") {
            let next = openat(folder, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            try #require(next >= 0, "Owned scratch component \(component) failed no-follow traversal with errno \(errno)")
            _ = close(folder)
            folder = next
        }
        var info = stat()
        try #require(fstat(folder, &info) == 0)
        #expect(info.st_uid == getuid())
        #expect((info.st_mode & 0o077) == 0)
    }

    @Test func storeRoundTripsAndStaleSaveCannotReplaceNewerCheckpoint() async throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let store = try scratch.store()
        #expect(try await store.list().records.isEmpty)
        var history = try fresh()
        let first = try await store.save(history, now: date)
        #expect(first.directorySynced && first.warnings.isEmpty && first.retention.failures.isEmpty)
        #expect(try await store.load(id: history.id) == history)
        let stale = history
        try history.appendMessage(role: .assistant, text: "Here is the explanation.", at: date)
        _ = try await store.save(history, expecting: .checkpoint(first.checkpointID), now: date)
        await #expect(throws: ExplanationHistoryStore.StoreError.conflict) {
            try await store.save(stale, expecting: .checkpoint(first.checkpointID), now: date)
        }
        #expect(try await store.load(id: history.id) == history)
        #expect(try await store.list().records.first?.checkpointID == history.lastCheckpointID)
        #expect(try await store.list().records.first?.sessionID == history.canonicalScene.sessionID)
        try await store.delete(id: history.id)
        await #expect(throws: ExplanationHistoryStore.StoreError.notFound) { try await store.load(id: history.id) }
    }

    @Test func everyPrecommitFaultPreservesOldRecordAndRemovesTemporaryFile() async throws {
        for stage in [ExplanationHistoryStore.FaultStage.afterTempCreate, .afterTempWrite, .beforeCommit] {
            let scratch = try Scratch(); defer { scratch.remove() }
            let store = try scratch.store(); var history = try fresh()
            let first = try await store.save(history, now: date)
            let bytes = try Data(contentsOf: scratch.file(history))
            try history.appendMessage(role: .user, text: "An unsaved change", at: date)
            let faulty = try scratch.store(fault: { if $0 == stage { throw InjectedFailure() } })
            await #expect(throws: InjectedFailure()) {
                try await faulty.save(history, expecting: .checkpoint(first.checkpointID), now: date)
            }
            #expect(try Data(contentsOf: scratch.file(history)) == bytes)
            #expect(try scratch.names() == [".history.lock", ExplanationHistoryStore.fileName(history.id)])
        }
    }

    @Test func directorySyncFailureReturnsSavedWarningAndCommittedData() async throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let store = try scratch.store(fault: { if $0 == .beforeDirectorySync { throw InjectedFailure() } })
        let history = try fresh()
        let receipt = try await store.save(history, now: date)
        #expect(!receipt.directorySynced && receipt.warnings.count == 1)
        #expect(try await store.load(id: history.id) == history)
    }

    @Test func retentionRemovesOldRecordsAndDeleteFailureIsVisibleAfterSuccessfulSave() async throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let policy = ExplanationHistoryStore.Policy(maxRecords: 1)
        let normal = try scratch.store(policy: policy)
        let first = try fresh(); _ = try await normal.save(first, now: date)
        let second = try ExplanationHistory(scene: .init(sessionID: UUID(), sceneID: UUID()), title: "Second", at: date.addingTimeInterval(1))
        let faulty = try scratch.store(policy: policy, fault: { if $0 == .beforeDelete { throw InjectedFailure() } })
        let receipt = try await faulty.save(second, now: date.addingTimeInterval(1))
        #expect(receipt.retention.deletedIDs.isEmpty && receipt.retention.failures.count == 1)
        #expect(receipt.retention.remainingRecords == 2)
        #expect(try await normal.load(id: second.id) == second)
        await #expect(throws: InjectedFailure()) { try await faulty.delete(id: first.id) }
        #expect(try await normal.load(id: first.id) == first)
        let repaired = try await normal.enforceRetention(now: date.addingTimeInterval(2))
        #expect(repaired.deletedIDs == [first.id] && repaired.failures.isEmpty && repaired.remainingRecords == 1)
    }

    @Test func expiredRecordsAreRemovedButCorruptAndUnknownFilesAreReportedOrPreserved() async throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let store = try scratch.store(policy: .init(maxAge: 1))
        let expired = try fresh(); _ = try await store.save(expired, now: date)
        let corruptID = UUID()
        let corrupt = scratch.root.appendingPathComponent(ExplanationHistoryStore.fileName(corruptID))
        try Data("not-json".utf8).write(to: corrupt)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: corrupt.path)
        let unknown = scratch.root.appendingPathComponent("keep-me.txt")
        try Data("untouched".utf8).write(to: unknown)
        let report = try await store.enforceRetention(now: date.addingTimeInterval(2))
        #expect(report.deletedIDs == [expired.id] && report.failures.map(\.id) == [corruptID])
        #expect(try Data(contentsOf: corrupt) == Data("not-json".utf8))
        #expect(try Data(contentsOf: unknown) == Data("untouched".utf8))
        try await store.delete(id: corruptID)
        #expect(!FileManager.default.fileExists(atPath: corrupt.path))
    }

    @Test func ancestorAndLeafSymlinksNeverRedirectHistoryOperations() async throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let outside = scratch.base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: scratch.root, withDestinationURL: outside)
        let store = try scratch.store(); let history = try fresh()
        await #expect(throws: ExplanationHistoryStore.StoreError.unsafePath) { try await store.save(history, now: date) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        try FileManager.default.removeItem(at: scratch.root)
        _ = try await store.save(history, now: date)
        try FileManager.default.removeItem(at: scratch.file(history))
        let target = outside.appendingPathComponent("protected.json")
        let sentinel = Data("do not touch".utf8); try sentinel.write(to: target)
        try FileManager.default.createSymbolicLink(at: scratch.file(history), withDestinationURL: target)
        await #expect(throws: ExplanationHistoryStore.StoreError.unsafeFile) { try await store.load(id: history.id) }
        await #expect(throws: ExplanationHistoryStore.StoreError.unsafeFile) { try await store.delete(id: history.id) }
        #expect(try Data(contentsOf: target) == sentinel)
    }

    @Test func hardLinksAndFIFOAreRefusedWithoutBlockingOrDeletingTargets() async throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let store = try scratch.store(); let history = try fresh(); _ = try await store.save(history, now: date)
        let linked = scratch.base.appendingPathComponent("linked")
        #expect(link(scratch.file(history).path, linked.path) == 0)
        await #expect(throws: ExplanationHistoryStore.StoreError.unsafeFile) { try await store.load(id: history.id) }
        await #expect(throws: ExplanationHistoryStore.StoreError.unsafeFile) { try await store.delete(id: history.id) }
        try FileManager.default.removeItem(at: linked)
        try FileManager.default.removeItem(at: scratch.file(history))
        #expect(mkfifo(scratch.file(history).path, mode_t(0o600)) == 0)
        await #expect(throws: ExplanationHistoryStore.StoreError.unsafeFile) { try await store.load(id: history.id) }
        await #expect(throws: ExplanationHistoryStore.StoreError.unsafeFile) { try await store.delete(id: history.id) }
    }

    @Test func diskBudgetAndOversizeReadAreRejectedBeforeReplacement() async throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let history = try fresh()
        let tiny = try scratch.store(policy: .init(maxTotalBytes: 64))
        await #expect(throws: ExplanationHistoryStore.StoreError.tooLarge) { try await tiny.save(history, now: date) }
        #expect(!FileManager.default.fileExists(atPath: scratch.root.path))
        let store = try scratch.store(); _ = try await store.save(history, now: date)
        let file = open(scratch.file(history).path, O_WRONLY | O_NOFOLLOW)
        #expect(file >= 0)
        if file >= 0 { #expect(ftruncate(file, off_t(ExplanationHistory.maxRecordBytes + 1)) == 0); _ = close(file) }
        await #expect(throws: ExplanationHistoryStore.StoreError.tooLarge) { try await store.load(id: history.id) }
        try await store.delete(id: history.id)
    }
}
