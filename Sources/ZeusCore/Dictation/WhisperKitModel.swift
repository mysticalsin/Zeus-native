import Foundation

/// Where the WhisperKit CoreML model lives and whether it is complete. The model downloads only
/// when the person clicks Download in Settings, into ~/Library/Application Support/Zeus/models/whisperkit.
public struct WhisperKitModelStore: Sendable {
    /// The compressed large-v3 turbo build in argmaxinc/whisperkit-coreml (about 632 MB).
    public static let variant = WhisperKitCLI.model
    public static let repo = "argmaxinc/whisperkit-coreml"
    public static let requiredFolders = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
    static let marker = ".zeus-complete"

    /// The folder handed to the downloader as its base.
    public let root: URL

    public init(root: URL = WhisperKitModelStore.defaultRoot) { self.root = root }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/models/whisperkit", isDirectory: true)
    }

    /// Where the Hugging Face client puts the variant under `root`.
    public var modelFolder: URL {
        root.appendingPathComponent("models/\(Self.repo)/openai_whisper-\(Self.variant)", isDirectory: true)
    }

    /// Complete means the three CoreML models are there and a finished download left its marker
    /// (a cancelled or failed one has no marker, so it is never mistaken for ready).
    public var isDownloaded: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: modelFolder.appendingPathComponent(Self.marker).path)
            && Self.requiredFolders.allSatisfy { fm.fileExists(atPath: modelFolder.appendingPathComponent($0).path) }
    }

    public func markComplete() throws {
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        try Data().write(to: modelFolder.appendingPathComponent(Self.marker))
    }
}

/// Fetches the model. The real one wraps WhisperKit.download; tests pass a fake.
public protocol WhisperKitModelDownloader: Sendable {
    func download(into store: WhisperKitModelStore, progress: @escaping @Sendable (Double) -> Void) async throws
}

/// Idle, downloading with progress, failed with a message. Cancel returns to idle.
public final class WhisperKitDownloadMachine: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case downloading(Double)
        case failed(String)
    }

    private let lock = NSLock()
    private var current = State.idle
    private var task: Task<Void, Never>?
    private let store: WhisperKitModelStore
    private let downloader: any WhisperKitModelDownloader

    public init(store: WhisperKitModelStore, downloader: any WhisperKitModelDownloader) {
        self.store = store
        self.downloader = downloader
    }

    public var state: State { lock.withLock { current } }

    /// Starts the download; a second call while one runs joins it. Returns when it ends.
    @discardableResult
    public func start(progress report: (@Sendable (Double) -> Void)? = nil) async -> State {
        let running: Task<Void, Never> = lock.withLock {
            if let task { return task }
            current = .downloading(0)
            let task = Task { [self] in
                do {
                    try await downloader.download(into: store) { fraction in
                        let clamped = min(max(fraction, 0), 1)
                        self.lock.withLock {
                            if case .downloading = self.current { self.current = .downloading(clamped) }
                        }
                        report?(clamped)
                    }
                    try Task.checkCancellation()
                    try store.markComplete()
                    lock.withLock { current = .idle }
                } catch {
                    lock.withLock {
                        current = Task.isCancelled || error is CancellationError ? .idle : .failed(error.localizedDescription)
                    }
                }
            }
            self.task = task
            return task
        }
        await running.value
        lock.withLock { task = nil }
        return state
    }

    public func cancel() {
        let running = lock.withLock { task }
        running?.cancel()
    }
}
