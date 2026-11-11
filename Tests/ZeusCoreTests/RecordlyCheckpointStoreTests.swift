import Foundation
import Testing
@testable import ZeusCore

/// Filesystem tests use only fresh canonical scratch roots under the temp directory. Nothing here touches
/// Application Support, defaults, the external backup volume, or any user file.
@Suite("Recordly checkpoint store")
struct RecordlyCheckpointStoreTests {
    private struct InjectedFault: Error, Equatable {}

    private struct Scratch {
        let root: String
        var mediaRoot: String { root + "/media" }
        var checkpointRoot: String { mediaRoot + "/Checkpoints" }
        var outside: String { root + "/outside" }
        var recordPath: String { checkpointRoot + "/" + RecordlyCheckpointStore.recordName }

        static func make() throws -> Scratch {
            // Darwin realpath keeps "/private/var/..."; Foundation's resolvingSymlinksInPath strips "/private",
            // leaving the "/var" symlink that the store correctly refuses.
            let tmp = NSTemporaryDirectory()
            var canonical = tmp
            if let resolved = realpath(tmp, nil) {
                canonical = String(cString: resolved)
                free(resolved)
            }
            let base = URL(fileURLWithPath: canonical, isDirectory: true)
            let dir = base.appendingPathComponent("zeus-recordly-ckpt-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let scratch = Scratch(root: dir.path)
            try FileManager.default.createDirectory(atPath: scratch.mediaRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: scratch.outside, withIntermediateDirectories: true)
            return scratch
        }

        func remove() { try? FileManager.default.removeItem(atPath: root) }

        func media(_ relative: String = "capture.mp4", bytes: Int = 16) throws -> String {
            let path = mediaRoot + "/" + relative
            try Data(repeating: 7, count: bytes).write(to: URL(fileURLWithPath: path))
            return path
        }

        func store(
            maxRecordBytes: Int = RecordlyCheckpointStore.defaultMaxRecordBytes,
            faultHook: (@Sendable (RecordlyCheckpointStore.FaultStage) throws -> Void)? = nil
        ) -> RecordlyCheckpointStore {
            RecordlyCheckpointStore(
                mediaRoot: mediaRoot,
                checkpointRoot: checkpointRoot,
                maxRecordBytes: maxRecordBytes,
                faultHook: faultHook
            )
        }

        func contents(_ path: String) throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: path).sorted()
        }

        func writeRecord(_ data: Data) throws {
            try FileManager.default.createDirectory(atPath: checkpointRoot, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: recordPath))
        }
    }

    // iso8601 coding drops sub-second precision, so fixtures use whole-second dates.
    private func project(_ mediaPath: String, quality: RecordlyExportQuality = .balanced) -> RecordlyProject {
        var project = RecordlyProject(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .display(id: 17),
            audio: RecordlyAudioOptions(microphone: true, systemAudio: false),
            rawMediaPath: mediaPath,
            trimStart: 1.5,
            trimEnd: 9.25,
            export: RecordlyExportSettings(preset: .uhd4K, quality: quality, formats: [.mp4, .gif]),
            frameStyle: RecordlyFrameStyle(padding: 8, cornerRadius: 4, shadowOpacity: 0.5, backgroundHex: nil),
            loopCursor: true
        )
        project.version = RecordlyProject.formatVersion
        return project
    }

    // MARK: Codec and settings

    @Test func saveThenLoadRoundTripsProjectAndSettings() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let saved = project(try scratch.media())
        let store = scratch.store()
        try store.save(saved)
        guard case .found(let loaded, let mediaURL) = try store.load() else {
            Issue.record("Expected the committed checkpoint to load.")
            return
        }
        #expect(loaded == saved)
        #expect(loaded.export.preset == .uhd4K)
        #expect(loaded.export.formats == [.mp4, .gif])
        #expect(loaded.frameStyle.backgroundHex == nil)
        #expect(mediaURL.path == saved.rawMediaPath)
    }

    @Test func regionSourceRoundTrips() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        var saved = project(try scratch.media())
        saved.source = .region(x: 1, y: 2, width: 30, height: 40)
        let store = scratch.store()
        try store.save(saved)
        guard case .found(let loaded, _) = try store.load() else {
            Issue.record("Expected region project to load.")
            return
        }
        #expect(loaded.source == .region(x: 1, y: 2, width: 30, height: 40))
    }

    @Test func loadWithNoCheckpointFolderOrRecordIsAbsent() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        #expect(try scratch.store().load() == .absent)
        try FileManager.default.createDirectory(atPath: scratch.checkpointRoot, withIntermediateDirectories: true)
        #expect(try scratch.store().load() == .absent)
    }

    // MARK: Rejection of bad records

    @Test func unsupportedVersionIsRejectedOnSaveAndLoadWithoutModifyingRecord() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        var future = project(try scratch.media())
        future.version = 99
        #expect(throws: RecordlyCheckpointStore.StoreError.unsupportedVersion(99)) {
            try scratch.store().save(future)
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))

        let encoded = try future.encoded()
        try scratch.writeRecord(encoded)
        #expect(throws: RecordlyCheckpointStore.StoreError.unsupportedVersion(99)) {
            try scratch.store().load()
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath)) == encoded)
    }

    @Test func corruptRecordsAreRejectedAndLeftInPlace() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        for garbage in ["not json", "{\"version\":1}", "{\"version\":\"one\"}", ""] {
            let data = Data(garbage.utf8)
            try scratch.writeRecord(data)
            #expect(throws: RecordlyCheckpointStore.StoreError.corrupt) {
                try scratch.store().load()
            }
            #expect(try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath)) == data)
        }
    }

    @Test func oversizeRecordIsRejectedOnLoadAndSaveWithoutChange() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let saved = project(try scratch.media())
        try scratch.store().save(saved)
        let before = try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath))

        #expect(throws: RecordlyCheckpointStore.StoreError.tooLarge) {
            try scratch.store(maxRecordBytes: 64).load()
        }
        #expect(throws: RecordlyCheckpointStore.StoreError.tooLarge) {
            try scratch.store(maxRecordBytes: 64).save(saved)
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath)) == before)
        #expect(try scratch.contents(scratch.checkpointRoot) == [RecordlyCheckpointStore.recordName])
    }

    @Test func oversizeSaveDoesNotCreateCheckpointFolder() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let saved = project(try scratch.media())
        #expect(throws: RecordlyCheckpointStore.StoreError.tooLarge) {
            try scratch.store(maxRecordBytes: 64).save(saved)
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    // MARK: Transactional write

    @Test func injectedFaultAtEveryStageKeepsPriorRecordAndLeavesNoTemp() throws {
        for stage in RecordlyCheckpointStore.FaultStage.allCases {
            let scratch = try Scratch.make()
            defer { scratch.remove() }
            let first = project(try scratch.media(), quality: .light)
            let second = project(try scratch.media(), quality: .high)
            try scratch.store().save(first)

            let faulty = scratch.store(faultHook: { reached in
                if reached == stage { throw InjectedFault() }
            })
            #expect(throws: InjectedFault()) { try faulty.save(second) }

            #expect(try scratch.contents(scratch.checkpointRoot) == [RecordlyCheckpointStore.recordName])
            guard case .found(let loaded, _) = try scratch.store().load() else {
                Issue.record("Prior record must still load after a fault at \(stage).")
                continue
            }
            #expect(loaded == first)
        }
    }

    @Test func faultOnFirstSaveLeavesNoRecord() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let faulty = scratch.store(faultHook: { stage in
            if stage == .beforeRename { throw InjectedFault() }
        })
        #expect(throws: InjectedFault()) { try faulty.save(project(try scratch.media())) }
        // An absent Checkpoints folder also means no record was committed.
        if FileManager.default.fileExists(atPath: scratch.checkpointRoot) {
            #expect(try scratch.contents(scratch.checkpointRoot).isEmpty)
        }
        #expect(try scratch.store().load() == .absent)
    }

    @Test func leftoverTempFileIsNeverDiscoveredAsARecord() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(atPath: scratch.checkpointRoot, withIntermediateDirectories: true)
        let saved = project(try scratch.media())
        let temp = scratch.checkpointRoot + "/.latest-orphan.tmp"
        try (try saved.encoded()).write(to: URL(fileURLWithPath: temp))
        #expect(try scratch.store().load() == .absent)
        #expect(FileManager.default.fileExists(atPath: temp))
    }

    @Test func repeatedCommitReplacesRecordAtomically() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let store = scratch.store()
        let first = project(try scratch.media(), quality: .light)
        let second = project(try scratch.media(), quality: .high)
        try store.save(first)
        try store.save(second)
        try store.save(second)
        guard case .found(let loaded, _) = try store.load() else {
            Issue.record("Expected the latest record.")
            return
        }
        #expect(loaded == second)
        #expect(try scratch.contents(scratch.checkpointRoot) == [RecordlyCheckpointStore.recordName])
    }

    // MARK: Trusted roots and escapes

    @Test func relativeOutOfRootAndDotDotMediaAreRefusedWithoutCreatingFolders() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let outsideFile = scratch.outside + "/capture.mp4"
        try Data(repeating: 1, count: 8).write(to: URL(fileURLWithPath: outsideFile))
        let siblingRoot = scratch.root + "/media-evil"
        try FileManager.default.createDirectory(atPath: siblingRoot, withIntermediateDirectories: true)
        let siblingFile = siblingRoot + "/capture.mp4"
        try Data(repeating: 1, count: 8).write(to: URL(fileURLWithPath: siblingFile))
        _ = try scratch.media()

        let rejected = [
            "capture.mp4",
            "./media/capture.mp4",
            outsideFile,
            siblingFile,
            scratch.mediaRoot,
            scratch.mediaRoot + "/",
            scratch.mediaRoot + "/../outside/capture.mp4",
            scratch.mediaRoot + "/./capture.mp4",
            scratch.mediaRoot + "//capture.mp4",
            scratch.checkpointRoot + "/" + RecordlyCheckpointStore.recordName
        ]
        for path in rejected {
            #expect(throws: RecordlyCheckpointStore.StoreError.mediaOutsideTrustedRoot, "\(path)") {
                try scratch.store().save(project(path))
            }
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    @Test func untrustedMediaInsideRecordIsRefusedOnLoad() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let outsideFile = scratch.outside + "/capture.mp4"
        try Data(repeating: 1, count: 8).write(to: URL(fileURLWithPath: outsideFile))
        try scratch.writeRecord(try project(outsideFile).encoded())
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaOutsideTrustedRoot) {
            try scratch.store().load()
        }
    }

    @Test func invalidRootsAreRejected() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        let relativeRoot = RecordlyCheckpointStore(mediaRoot: "media", checkpointRoot: scratch.checkpointRoot)
        #expect(throws: RecordlyCheckpointStore.StoreError.invalidRoot("recording")) {
            try relativeRoot.save(project(media))
        }
        let dotDotRoot = RecordlyCheckpointStore(mediaRoot: scratch.mediaRoot, checkpointRoot: scratch.mediaRoot + "/x/../Checkpoints")
        #expect(throws: RecordlyCheckpointStore.StoreError.invalidRoot("checkpoint")) {
            try dotDotRoot.load()
        }
    }

    @Test func leafMediaSymlinkIsRefused() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let target = scratch.outside + "/real.mp4"
        try Data(repeating: 1, count: 8).write(to: URL(fileURLWithPath: target))
        let link = scratch.mediaRoot + "/link.mp4"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        #expect(throws: RecordlyCheckpointStore.StoreError.pathEscape) {
            try scratch.store().save(project(link))
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    @Test func ancestorMediaSymlinkIsRefused() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        try Data(repeating: 1, count: 8).write(to: URL(fileURLWithPath: scratch.outside + "/capture.mp4"))
        try FileManager.default.createSymbolicLink(atPath: scratch.mediaRoot + "/dir", withDestinationPath: scratch.outside)
        #expect(throws: RecordlyCheckpointStore.StoreError.pathEscape) {
            try scratch.store().save(project(scratch.mediaRoot + "/dir/capture.mp4"))
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    @Test func symlinkInTrustedRootAncestorIsRefused() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        _ = try scratch.media()
        let alias = scratch.root + "-alias"
        try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: scratch.root)
        defer { try? FileManager.default.removeItem(atPath: alias) }
        let viaAlias = RecordlyCheckpointStore(mediaRoot: alias + "/media", checkpointRoot: alias + "/media/Checkpoints")
        #expect(throws: RecordlyCheckpointStore.StoreError.pathEscape) {
            try viaAlias.save(project(alias + "/media/capture.mp4"))
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    @Test func checkpointFolderSymlinkIsRefusedOnSaveAndLoad() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        try FileManager.default.createSymbolicLink(atPath: scratch.checkpointRoot, withDestinationPath: scratch.outside)
        #expect(throws: RecordlyCheckpointStore.StoreError.pathEscape) {
            try scratch.store().save(project(media))
        }
        #expect(throws: RecordlyCheckpointStore.StoreError.pathEscape) {
            try scratch.store().load()
        }
        #expect(try scratch.contents(scratch.outside).isEmpty)
    }

    @Test func recordLeafSymlinkIsRefusedOnLoad() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        let external = scratch.outside + "/record.json"
        try (try project(media).encoded()).write(to: URL(fileURLWithPath: external))
        try FileManager.default.createDirectory(atPath: scratch.checkpointRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: scratch.recordPath, withDestinationPath: external)
        #expect(throws: RecordlyCheckpointStore.StoreError.pathEscape) {
            try scratch.store().load()
        }
    }

    // MARK: Media state

    @Test func missingEmptyAndNonRegularMediaAreRefusedOnSave() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaMissing) {
            try scratch.store().save(project(scratch.mediaRoot + "/missing.mp4"))
        }
        let empty = try scratch.media("empty.mp4", bytes: 0)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaEmpty) {
            try scratch.store().save(project(empty))
        }
        try FileManager.default.createDirectory(atPath: scratch.mediaRoot + "/folder.mp4", withIntermediateDirectories: true)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaNotRegularFile) {
            try scratch.store().save(project(scratch.mediaRoot + "/folder.mp4"))
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    @Test func mediaLostAfterSaveFailsLoadButKeepsRecord() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        try scratch.store().save(project(media))
        let before = try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath))
        try FileManager.default.removeItem(atPath: media)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaMissing) {
            try scratch.store().load()
        }
        _ = try scratch.media(bytes: 0)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaEmpty) {
            try scratch.store().load()
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath)) == before)
    }

    @Test func saveNeverTouchesRawMedia() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media(bytes: 33)
        let before = try Data(contentsOf: URL(fileURLWithPath: media))
        try scratch.store().save(project(media))
        _ = try scratch.store().load()
        #expect(try Data(contentsOf: URL(fileURLWithPath: media)) == before)
    }

    // MARK: Flow (same decision seam the Controller drives)

    @Test func finalizeCommitsAndRetiresLazyRestore() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        let saved = project(media)
        var flow = RecordlyCheckpointFlow()
        let result = flow.finalize(project: saved, mediaURL: URL(fileURLWithPath: media), store: scratch.store())
        #expect(result == .committed)
        #expect(!flow.hasPending)
        #expect(flow.restoreIfNeeded(store: scratch.store()) == .skipped)
        guard case .found(let loaded, _) = try scratch.store().load() else {
            Issue.record("Finalize must have written the record.")
            return
        }
        #expect(loaded == saved)
    }

    @Test func failedFinalizeRetainsSameProjectAndRetryCommitsIt() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        let saved = project(media)
        let url = URL(fileURLWithPath: media)
        let faulty = scratch.store(faultHook: { stage in
            if stage == .afterTempWrite { throw InjectedFault() }
        })
        var flow = RecordlyCheckpointFlow()
        guard case .failed(let reason) = flow.finalize(project: saved, mediaURL: url, store: faulty) else {
            Issue.record("An injected save fault must surface as a failure.")
            return
        }
        #expect(!reason.isEmpty)
        #expect(flow.pending == RecordlyCheckpointFlow.Pending(project: saved, mediaURL: url))
        #expect(try scratch.store().load() == .absent)

        guard case .failed = flow.retryPending(store: faulty) else {
            Issue.record("Retry against a still-failing store must fail again.")
            return
        }
        #expect(flow.pending?.project == saved)

        #expect(flow.retryPending(store: scratch.store()) == .committed)
        #expect(!flow.hasPending)
        guard case .found(let loaded, _) = try scratch.store().load() else {
            Issue.record("Retry must commit the retained project.")
            return
        }
        #expect(loaded == saved)
        #expect(flow.retryPending(store: scratch.store()) == nil)
    }

    @Test func finalizeWithUnavailableStoreFailsAndKeepsPending() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        var flow = RecordlyCheckpointFlow()
        guard case .failed = flow.finalize(project: project(media), mediaURL: URL(fileURLWithPath: media), store: nil) else {
            Issue.record("A missing store must not be reported as success.")
            return
        }
        #expect(flow.hasPending)
    }

    @Test func finalizeWithMediaOutsideTrustedRootFailsTruthfully() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let outsideFile = scratch.outside + "/capture.mp4"
        try Data(repeating: 1, count: 8).write(to: URL(fileURLWithPath: outsideFile))
        var flow = RecordlyCheckpointFlow()
        guard case .failed(let reason) = flow.finalize(
            project: project(outsideFile),
            mediaURL: URL(fileURLWithPath: outsideFile),
            store: scratch.store()
        ) else {
            Issue.record("Out-of-root media must not report a committed checkpoint.")
            return
        }
        #expect(reason.contains("outside Zeus's recordings folder"))
        #expect(flow.hasPending)
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    @Test func restoreRunsOnceAndSkipsAfterwards() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let saved = project(try scratch.media())
        try scratch.store().save(saved)

        var evaluations = 0
        let store = scratch.store()
        func lazyStore() -> RecordlyCheckpointStore? {
            evaluations += 1
            return store
        }
        var flow = RecordlyCheckpointFlow()
        guard case .restored(let restored, let mediaURL) = flow.restoreIfNeeded(store: lazyStore()) else {
            Issue.record("Expected the saved checkpoint to restore.")
            return
        }
        #expect(restored == saved)
        #expect(mediaURL.path == saved.rawMediaPath)
        #expect(flow.restoreIfNeeded(store: lazyStore()) == .skipped)
        #expect(evaluations == 1)
    }

    @Test func restoreWithNoCheckpointOrNoStoreDefersToProvider() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        var flow = RecordlyCheckpointFlow()
        #expect(flow.restoreIfNeeded(store: scratch.store()) == .noCheckpoint)
        #expect(flow.restoreIfNeeded(store: scratch.store()) == .skipped)
        var noStore = RecordlyCheckpointFlow()
        #expect(noStore.restoreIfNeeded(store: nil) == .noCheckpoint)
    }

    @Test func invalidRestoreFailsVisiblyOnceAndLeavesEverythingInPlace() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        let garbage = Data("{broken".utf8)
        try scratch.writeRecord(garbage)
        var flow = RecordlyCheckpointFlow()
        guard case .failed(let reason) = flow.restoreIfNeeded(store: scratch.store()) else {
            Issue.record("A corrupt checkpoint must produce a visible failure.")
            return
        }
        #expect(reason.contains("left untouched"))
        #expect(flow.restoreIfNeeded(store: scratch.store()) == .skipped)
        #expect(try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath)) == garbage)
        #expect(FileManager.default.fileExists(atPath: media))
    }

    @Test func missingMediaRestoreFailsVisiblyWithoutDeletingRecord() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        try scratch.store().save(project(media))
        try FileManager.default.removeItem(atPath: media)
        var flow = RecordlyCheckpointFlow()
        guard case .failed(let reason) = flow.restoreIfNeeded(store: scratch.store()) else {
            Issue.record("Missing media must produce a visible failure.")
            return
        }
        #expect(reason.contains("missing"))
        #expect(FileManager.default.fileExists(atPath: scratch.recordPath))
    }

    // MARK: Hardlinks and pinned media authority (synthetic scratch roots only)

    @Test func hardLinkedMediaIsRefusedOnSave() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        try FileManager.default.linkItem(atPath: media, toPath: scratch.outside + "/alias.mp4")
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaHardLinked) {
            try scratch.store().save(project(media))
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    @Test func hardLinkedMediaIsRefusedOnLoadAfterSave() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        try scratch.store().save(project(media))
        let before = try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath))
        try FileManager.default.linkItem(atPath: media, toPath: scratch.outside + "/alias.mp4")
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaHardLinked) {
            try scratch.store().load()
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: scratch.recordPath)) == before)
    }

    @Test func hardLinkedRecordIsRefusedOnLoad() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        try scratch.store().save(project(media))
        try FileManager.default.linkItem(atPath: scratch.recordPath, toPath: scratch.outside + "/record-alias.json")
        #expect(throws: RecordlyCheckpointStore.StoreError.checkpointHardLinked) {
            try scratch.store().load()
        }
    }

    @Test func restoredMediaStaysPinnedAfterRenameAndSymlinkSwap() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media(bytes: 16)
        try scratch.store().save(project(media))
        guard case .found(_, let handle) = try scratch.store().load() else {
            Issue.record("Expected the checkpoint to load.")
            return
        }
        let original = Data(repeating: 7, count: 16)

        // Rename away and put a different file at the validated path.
        try FileManager.default.moveItem(atPath: media, toPath: scratch.outside + "/moved.mp4")
        try Data(repeating: 9, count: 16).write(to: URL(fileURLWithPath: media))
        #expect(try readAll(handle) == original)

        // Replace the path with a symlink to an outside file.
        try FileManager.default.removeItem(atPath: media)
        try FileManager.default.createSymbolicLink(atPath: media, withDestinationPath: scratch.outside + "/moved.mp4")
        #expect(try readAll(handle) == original)
        try handle.revalidate()
    }

    @Test func revalidateDetectsHardLinkCreatedAfterValidation() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        try scratch.store().save(project(media))
        guard case .found(_, let handle) = try scratch.store().load() else {
            Issue.record("Expected the checkpoint to load.")
            return
        }
        try handle.revalidate()
        try FileManager.default.linkItem(atPath: media, toPath: scratch.outside + "/late-alias.mp4")
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaHardLinked) { try handle.revalidate() }
    }

    @Test func handleReleaseIsIdempotentAndBlocksFurtherUse() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        try scratch.store().save(project(try scratch.media()))
        guard case .found(_, let handle) = try scratch.store().load() else {
            Issue.record("Expected the checkpoint to load.")
            return
        }
        #expect(!handle.isReleased)
        #expect(handle.byteCount == 16)
        handle.close()
        handle.close()
        #expect(handle.isReleased)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaReleased) { try handle.revalidate() }
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaReleased) { try handle.withDescriptor { _ in 0 } }
    }

    @Test func flowForwardsTheSameValidatedHandle() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        try scratch.store().save(project(try scratch.media()))
        var flow = RecordlyCheckpointFlow()
        guard case .restored(_, let handle) = flow.restoreIfNeeded(store: scratch.store()) else {
            Issue.record("Expected the saved checkpoint to restore.")
            return
        }
        #expect(!handle.isReleased)
        try handle.revalidate()
    }

    // MARK: Bounded descriptor reads (synthetic scratch roots only)

    private func patterned(_ count: Int) -> Data { Data((0..<count).map { UInt8($0 % 251) }) }

    private func pinned(_ scratch: Scratch, bytes: Int = 200_000) throws -> (path: String, handle: RecordlyValidatedMedia) {
        let path = scratch.mediaRoot + "/capture.mp4"
        try patterned(bytes).write(to: URL(fileURLWithPath: path))
        return (path, try scratch.store().openValidatedMedia(rawPath: path))
    }

    @Test func boundedReadReturnsRangesCapsChunksAndStopsAtEnd() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let (_, handle) = try pinned(scratch)
        let all = patterned(200_000)
        #expect(try handle.readBounded(offset: 10, length: 100) == all[10..<110])
        let capped = try handle.readBounded(offset: 0, length: 1_000_000)
        #expect(capped.count == RecordlyValidatedMedia.maxReadChunk)
        #expect(capped == all[0..<RecordlyValidatedMedia.maxReadChunk])
        #expect(try handle.readBounded(offset: 199_990, length: 500) == all[199_990..<200_000])
        #expect(try handle.readBounded(offset: 200_000, length: 10).isEmpty)
        #expect(try handle.readBounded(offset: 5, length: 0).isEmpty)
        // Offsets and lengths at the integer limits neither overflow nor allocate.
        #expect(try handle.readBounded(offset: Int64.max, length: Int.max).isEmpty)
        #expect(try handle.readBounded(offset: 0, length: Int.max).count == RecordlyValidatedMedia.maxReadChunk)
        #expect(throws: RecordlyCheckpointStore.StoreError.readOutOfRange) { try handle.readBounded(offset: -1, length: 4) }
        #expect(throws: RecordlyCheckpointStore.StoreError.readOutOfRange) { try handle.readBounded(offset: 0, length: -1) }
    }

    @Test func boundedReadFailsClosedOnObservedSizeLinkAndRelease() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let (path, handle) = try pinned(scratch)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaChanged) {
            try handle.readBounded(offset: 0, length: 16, expectedSize: 199_999)
        }
        _ = try handle.readBounded(offset: 0, length: 16, expectedSize: 200_000)

        let writer = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try writer.truncate(atOffset: 100)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaChanged) {
            try handle.readBounded(offset: 0, length: 16, expectedSize: 200_000)
        }
        try writer.truncate(atOffset: 0)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaEmpty) { try handle.readBounded(offset: 0, length: 16) }
        try writer.truncate(atOffset: 200_000)
        try writer.close()

        try FileManager.default.linkItem(atPath: path, toPath: scratch.outside + "/late.mp4")
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaHardLinked) { try handle.readBounded(offset: 0, length: 16) }

        handle.close()
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaReleased) { try handle.readBounded(offset: 0, length: 16) }
    }

    @Test func boundedReadStaysOnPinnedInodeAfterRenameAndSymlinkSwap() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let (path, handle) = try pinned(scratch, bytes: 4096)
        let all = patterned(4096)
        try FileManager.default.moveItem(atPath: path, toPath: scratch.outside + "/moved.mp4")
        try Data(repeating: 9, count: 4096).write(to: URL(fileURLWithPath: path))
        #expect(try handle.readBounded(offset: 0, length: 4096) == all)
        try FileManager.default.removeItem(atPath: path)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: scratch.outside + "/moved.mp4")
        #expect(try handle.readBounded(offset: 100, length: 50) == all[100..<150])
    }

    @Test func boundedReadRefusesMediaOverThePreviewLimit() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let (path, handle) = try pinned(scratch, bytes: 16)
        let writer = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try writer.truncate(atOffset: UInt64(RecordlyValidatedMedia.maxPreviewBytes) + 1)
        try writer.close()
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaTooLargeForPreview) { try handle.readBounded(offset: 0, length: 16) }
    }

    private func largePinned(_ scratch: Scratch) throws -> (path: String, handle: RecordlyValidatedMedia) {
        let path = try scratch.media()
        let writer = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? writer.close() }
        let size = UInt64(RecordlyValidatedMedia.maxPreviewBytes) + 4096
        try writer.truncate(atOffset: size)
        try writer.seek(toOffset: size - 4)
        try writer.write(contentsOf: Data("tail".utf8))
        return (path, try scratch.store().openValidatedMedia(rawPath: path))
    }

    @Test func largeExportStreamsTailAndCapsAllocationWhilePreviewRemainsLimited() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let (_, handle) = try largePinned(scratch)
        defer { handle.close() }
        #expect(handle.byteCount > RecordlyValidatedMedia.maxPreviewBytes)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaTooLargeForPreview) {
            try handle.readBounded(offset: handle.byteCount - 4, length: 4)
        }
        #expect(try handle.readBounded(offset: handle.byteCount - 4, length: Int.max, purpose: .export) == Data("tail".utf8))
        #expect(try handle.readBounded(offset: 0, length: Int.max, purpose: .export).count == RecordlyValidatedMedia.maxReadChunk)
        #expect(try handle.readBounded(offset: handle.byteCount, length: 4, purpose: .export).isEmpty)
    }

    @Test func largeExportRejectsGrowthLinksAndReleasedAuthority() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let (path, handle) = try largePinned(scratch)
        defer { handle.close() }
        let writer = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try writer.truncate(atOffset: UInt64(handle.byteCount) + 1)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaChanged) {
            try handle.readBounded(offset: 0, length: 16, purpose: .export)
        }
        try writer.truncate(atOffset: UInt64(handle.byteCount))
        try writer.close()
        let alias = scratch.outside + "/alias.mp4"
        try FileManager.default.linkItem(atPath: path, toPath: alias)
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaHardLinked) {
            try handle.readBounded(offset: 0, length: 16, purpose: .export)
        }
        try FileManager.default.removeItem(atPath: alias)
        handle.close()
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaReleased) {
            try handle.readBounded(offset: 0, length: 16, purpose: .export)
        }
    }

    @Test func largeExportNeverReopensAReplacedPath() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let (path, handle) = try largePinned(scratch)
        defer { handle.close() }
        let moved = scratch.outside + "/moved.mp4"
        try FileManager.default.moveItem(atPath: path, toPath: moved)
        try Data("replacement".utf8).write(to: URL(fileURLWithPath: path))
        #expect(try handle.readBounded(offset: handle.byteCount - 4, length: 4, purpose: .export) == Data("tail".utf8))
        try FileManager.default.removeItem(atPath: path)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: moved)
        #expect(try handle.readBounded(offset: handle.byteCount - 4, length: 4, purpose: .export) == Data("tail".utf8))
    }

    @Test func openValidatedMediaAppliesTheTrustedRootAndLinkChecks() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        #expect(try scratch.store().openValidatedMedia(rawPath: media).byteCount == 16)
        let outsideFile = scratch.outside + "/capture.mp4"
        try Data(repeating: 1, count: 8).write(to: URL(fileURLWithPath: outsideFile))
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaOutsideTrustedRoot) {
            try scratch.store().openValidatedMedia(rawPath: outsideFile)
        }
        let link = scratch.mediaRoot + "/link.mp4"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: media)
        #expect(throws: RecordlyCheckpointStore.StoreError.pathEscape) { try scratch.store().openValidatedMedia(rawPath: link) }
        try FileManager.default.linkItem(atPath: media, toPath: scratch.outside + "/alias.mp4")
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaHardLinked) { try scratch.store().openValidatedMedia(rawPath: media) }
        #expect(!FileManager.default.fileExists(atPath: scratch.checkpointRoot))
    }

    @Test func discardPendingDropsAnAbandonedSaveWithoutTouchingFiles() throws {
        let scratch = try Scratch.make()
        defer { scratch.remove() }
        let media = try scratch.media()
        var flow = RecordlyCheckpointFlow()
        _ = flow.finalize(project: project(media), mediaURL: URL(fileURLWithPath: media), store: nil)
        #expect(flow.hasPending)
        flow.discardPending()
        #expect(!flow.hasPending)
        #expect(flow.retryPending(store: scratch.store()) == nil)
        #expect(FileManager.default.fileExists(atPath: media))
    }

    // MARK: Root consistency (no filesystem access)

    @Test func productionStoreRootsMatchTheCaptureMediaRoot() throws {
        guard let root = RecordlyCheckpointStore.productionMediaRootURL(),
              let store = RecordlyCheckpointStore.makeProduction()
        else {
            Issue.record("Application Support must resolve on this host.")
            return
        }
        #expect(store.mediaRoot == root.path)
        #expect(store.checkpointRoot == root.path + "/" + RecordlyCheckpointStore.checkpointDirectoryName)
        #expect(root.path.hasSuffix("/Zeus/Recordly"))
    }

    private func readAll(_ handle: RecordlyValidatedMedia) throws -> Data {
        try handle.withDescriptor { fd in
            var buffer = [UInt8](repeating: 0, count: 64)
            let got = buffer.withUnsafeMutableBytes { Darwin.pread(fd, $0.baseAddress, $0.count, 0) }
            return Data(buffer.prefix(max(got, 0)))
        }
    }

    // MARK: STATIC wiring (source text only; does not execute the Controller)

    @Test func staticQaDirectoryUsesTrustedRootAndNotExternalVolume() throws {
        let source = try controllerSource()
        let start = try #require(source.range(of: "static func qaDirectory() -> URL {"))
        let end = try #require(source.range(of: "func runDebug(plan:"))
        let body = String(source[start.lowerBound..<end.lowerBound])
        #expect(body.contains("RecordlyCheckpointStore.productionMediaRootURL()"))
        #expect(!body.contains("/Volumes"))
        #expect(!body.contains("Backup"))
    }

    @Test func staticControllerReleasesRestoredMediaOnResetAndNewRecording() throws {
        let source = try controllerSource()
        let finishStart = try #require(source.range(of: "private func finishRecording"))
        let finishEnd = try #require(source.range(of: "@ObservationIgnored private var checkpointFlow"))
        #expect(String(source[finishStart.lowerBound..<finishEnd.lowerBound]).contains("acquireMediaAuthority(for: built)"))
        let resetStart = try #require(source.range(of: "func reset() {"))
        let resetEnd = try #require(source.range(of: "static func qaDirectory()"))
        let reset = String(source[resetStart.lowerBound..<resetEnd.lowerBound])
        #expect(reset.contains("discardProjectBindings("))
        #expect(reset.contains("project = nil"))
        #expect(source.contains("case .restored(let restored, let media):"))
        #expect(source.contains("setMediaAuthority(media, reason: nil)"))
    }

    @Test func staticCheckpointFailureKeepsEditorWithSeparateWarningAndRetry() throws {
        let source = try controllerSource()
        let start = try #require(source.range(of: "private func applyCheckpointCommit"))
        let end = try #require(source.range(of: "func retryCheckpoint()"))
        let apply = String(source[start.lowerBound..<end.lowerBound])
        #expect(apply.contains("checkpointWarning = reason"))
        #expect(apply.contains("phase = .editor"))
        #expect(!apply.contains(".failed(\"") && !apply.contains("phase = .failed"))
        #expect(source.contains("func retryCheckpoint()"))
        let debugStart = try #require(source.range(of: "discardProjectBindings(reason: \"Debug"))
        let assign = try #require(source.range(of: "project = RecordlyProject(source: captureSource"))
        #expect(debugStart.lowerBound < assign.lowerBound)
        let page = try pageSource()
        #expect(page.contains("recordly.checkpointWarning"))
        #expect(page.contains("recordly.retryCheckpoint()"))
        #expect(page.contains("RecordlyMediaPreview(media: recordly.mediaAuthority"))
        #expect(!page.contains("Ready to export"))
    }

    @Test func staticLoaderIsDescriptorFedWithNoPathReopen() throws {
        let source = try sourceText("Sources/Zeus/Recordly/RecordlyMediaResource.swift")
        #expect(source.contains("AVAssetResourceLoaderDelegate"))
        #expect(source.contains("shouldWaitForLoadingOfRequestedResource"))
        #expect(source.contains("didCancel loadingRequest"))
        #expect(source.contains("media.readBounded("))
        #expect(source.contains("VideoPlayer(player:"))
        for forbidden in ["fileURLWithPath", "rawMediaPath", "lastMediaURL", "/dev/fd", "URLSession", "http", ".close()"] {
            #expect(!source.contains(forbidden), "\(forbidden)")
        }
    }

    @Test func staticControllerWiringUsesProductionStoreAndFlow() throws {
        let source = try controllerSource()
        let loadStart = try #require(source.range(of: "func loadSourceCatalog() async {"))
        let restoreCall = try #require(source.range(of: "if restoreCheckpointIfNeeded() { return }"))
        let providerCall = try #require(source.range(of: "await catalogProvider.loadCatalog()"))
        #expect(loadStart.lowerBound < restoreCall.lowerBound)
        #expect(restoreCall.lowerBound < providerCall.lowerBound)

        let finishStart = try #require(source.range(of: "private func finishRecording"))
        let finishEnd = try #require(source.range(of: "@ObservationIgnored private var checkpointFlow"))
        let finish = String(source[finishStart.lowerBound..<finishEnd.lowerBound])
        #expect(finish.contains("checkpointFlow.finalize("))
        #expect(!finish.contains("phase = .editor"))

        #expect(source.contains("checkpointFlow.restoreIfNeeded("))
        #expect(source.contains("checkpointFlow.retryPending("))
        #expect(source.contains("RecordlyCheckpointStore.makeProduction()"))
        #expect(!source.contains("RecordlyCheckpointStore("))
    }

    @Test func staticControllerInitDoesNotResolveCheckpointRoots() throws {
        let source = try controllerSource()
        let initStart = try #require(source.range(of: "init(catalogProvider"))
        let initEnd = try #require(source.range(of: "var isRecording: Bool"))
        let initBody = String(source[initStart.lowerBound..<initEnd.lowerBound])
        #expect(!initBody.contains("checkpoint"))
        #expect(!initBody.contains("Checkpoint"))
    }

    private func controllerSource() throws -> String {
        try sourceText("Sources/Zeus/Recordly/RecordlyController.swift")
    }

    private func pageSource() throws -> String {
        try sourceText("Sources/Zeus/Recordly/RecordlyPage.swift")
    }

    private func sourceText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
