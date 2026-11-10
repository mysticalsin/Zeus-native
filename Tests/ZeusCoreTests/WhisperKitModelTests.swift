import Foundation
import Testing
@testable import ZeusCore

private func tempStore() -> WhisperKitModelStore {
    WhisperKitModelStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("zeus-wk-\(UUID().uuidString)"))
}

private func plantModel(_ store: WhisperKitModelStore) throws {
    for name in WhisperKitModelStore.requiredFolders {
        try FileManager.default.createDirectory(at: store.modelFolder.appendingPathComponent(name), withIntermediateDirectories: true)
    }
}

private struct FakeDownloader: WhisperKitModelDownloader {
    var steps: [Double] = [0.25, 0.5, 1]
    var failure: String?
    var hang = false
    func download(into store: WhisperKitModelStore, progress: @escaping @Sendable (Double) -> Void) async throws {
        for step in steps { progress(step) }
        if hang { try await Task.sleep(nanoseconds: 60_000_000_000) }
        if let failure { throw NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        try plantModel(store)
    }
}

private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ v: Double) { lock.withLock { values.append(v) } }
    var all: [Double] { lock.withLock { values } }
}

@Suite struct WhisperKitModelTests {
    @Test func modelPathIsUnderApplicationSupport() {
        let root = WhisperKitModelStore.defaultRoot.path
        #expect(root.hasSuffix("Application Support/Zeus/models/whisperkit"))
        let folder = WhisperKitModelStore().modelFolder.path
        #expect(folder.hasSuffix("models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB"))
    }

    @Test func downloadedNeedsFilesAndMarker() throws {
        let store = tempStore()
        #expect(!store.isDownloaded)
        try plantModel(store)
        #expect(!store.isDownloaded, "model folders without the completion marker are a partial download")
        try store.markComplete()
        #expect(store.isDownloaded)
    }

    @Test func successfulDownloadReportsProgressAndFinishes() async throws {
        let store = tempStore()
        let machine = WhisperKitDownloadMachine(store: store, downloader: FakeDownloader())
        #expect(machine.state == .idle)
        let seen = Progress()
        let end = await machine.start { seen.add($0) }
        #expect(end == .idle)
        #expect(seen.all == [0.25, 0.5, 1])
        #expect(store.isDownloaded)
    }

    @Test func failedDownloadKeepsMessageAndNoMarker() async {
        let store = tempStore()
        let machine = WhisperKitDownloadMachine(store: store, downloader: FakeDownloader(failure: "offline"))
        let end = await machine.start()
        #expect(end == .failed("offline"))
        #expect(!store.isDownloaded)
    }

    @Test func cancelReturnsToIdleWithoutMarker() async throws {
        let store = tempStore()
        let machine = WhisperKitDownloadMachine(store: store, downloader: FakeDownloader(hang: true))
        let run = Task { await machine.start() }
        for _ in 0..<200 where machine.state == .idle { try await Task.sleep(nanoseconds: 10_000_000) }
        if case .downloading = machine.state {} else { Issue.record("expected downloading, got \(machine.state)") }
        machine.cancel()
        #expect(await run.value == .idle)
        #expect(!store.isDownloaded)
    }

    @Test func cancelLineAppearsOnlyWhenCancellable() {
        let plain = EngineStatusMapping.line(for: .whisperKit, availability: .downloading(0.5), selected: false)
        #expect(plain.action == .none && plain.actionTitle == nil)
        let cancellable = EngineStatusMapping.line(for: .whisperKit, availability: .downloading(0.5), selected: false, cancellable: true)
        #expect(cancellable.label == "Downloading 50 %" && cancellable.action == .cancel && cancellable.actionTitle == "Cancel")
        let idle = EngineStatusMapping.line(for: .whisperKit, availability: .notDownloaded, selected: false)
        #expect(idle.label == "Download 630 MB")
    }
}
