import Foundation
import WhisperKit
import ZeusCore

/// Whisper large-v3 turbo on the Neural Engine through Argmax's WhisperKit package (code MIT,
/// CoreML weights argmaxinc/whisperkit-coreml MIT, OpenAI Whisper weights MIT). The model
/// (about 632 MB) downloads only when the person clicks Download in Settings, into
/// ~/Library/Application Support/Zeus/models/whisperkit, and is prewarmed the first time it is used.
final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    let kind = TranscriptionEngineKind.whisperKit
    private let store: WhisperKitModelStore
    private let machine: WhisperKitDownloadMachine
    private let lock = NSLock()
    private var loading: Task<PipeBox, Error>?

    init(store: WhisperKitModelStore = WhisperKitModelStore(),
         downloader: any WhisperKitModelDownloader = HubModelDownloader()) {
        self.store = store
        machine = WhisperKitDownloadMachine(store: store, downloader: downloader)
    }

    /// The shared instance the picker and the controller use for the real model location.
    var isDownloaded: Bool { store.isDownloaded }
    var modelFolder: URL { store.modelFolder }

    func availability() async -> EngineAvailability {
        if case .downloading(let fraction) = machine.state { return .downloading(fraction) }
        return store.isDownloaded ? .ready : .notDownloaded
    }

    /// Downloads the model (progress 0...0.9), then loads and prewarms it (to 1) so the first
    /// dictation is quick and the tokenizer is cached for offline use.
    func prepare(progress report: (@Sendable (Double) -> Void)?) async throws {
        if !store.isDownloaded {
            let end = await machine.start { report?($0 * 0.9) }
            switch end {
            case .failed(let message): throw WhisperKitEngineError.download(message)
            case .downloading: break
            case .idle: break
            }
            guard store.isDownloaded else { throw CancellationError() }
        }
        report?(0.9)
        _ = try await loadedPipe()
        report?(1)
    }

    func cancelDownload() { machine.cancel() }

    /// The Whisper prompt for the vocabulary: Zeus builds the same short sentence for every Whisper engine.
    static func prompt(for hints: [String]) -> String { DictationVocabularyPrompt.whisperPrompt(terms: hints) }

    /// Prompt token ids for the decoder, special tokens dropped (the decoder adds its own).
    static func promptTokens(_ prompt: String, encode: (String) -> [Int], specialTokenBegin: Int) -> [Int]? {
        guard !prompt.isEmpty else { return nil }
        let tokens = encode(" " + prompt).filter { $0 < specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.noSpeech }
        guard store.isDownloaded else { throw TranscriptionError.notReady(kind) }
        let code = DictationLanguage.engineLanguageCode(for: language)
        let prompt = Self.prompt(for: hints)
        let pipe = try await loadedPipe().pipe
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = code
        options.detectLanguage = code == nil
        options.temperature = 0
        options.skipSpecialTokens = true
        options.withoutTimestamps = true
        // Only a prompt actually delivered to the tokenizer can be echoed by the model.
        let sentPrompt = pipe.tokenizer == nil ? "" : prompt
        return try await WhisperPromptRecovery.transcribe(sentPrompt: sentPrompt) { attempt in
            var attemptOptions = options
            if let tokenizer = pipe.tokenizer {
                attemptOptions.promptTokens = Self.promptTokens(attempt.prompt, encode: { tokenizer.encode(text: $0) },
                                                                specialTokenBegin: tokenizer.specialTokens.specialTokenBegin)
            }
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: attemptOptions)
            return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Loads and prewarms once; concurrent callers share the one load. A failed load is retried next time.
    private func loadedPipe() async throws -> PipeBox {
        let task: Task<PipeBox, Error> = lock.withLock {
            if let loading { return loading }
            let folder = store.modelFolder.path
            let tokenizers = store.root
            let task = Task {
                PipeBox(pipe: try await WhisperKit(WhisperKitConfig(downloadBase: store.root, modelFolder: folder, tokenizerFolder: tokenizers,
                                                      verbose: false, prewarm: true, load: true, download: false)))
            }
            loading = task
            return task
        }
        do {
            return try await task.value
        } catch {
            lock.withLock { loading = nil }
            throw error
        }
    }
}

/// WhisperKit is not Sendable; the engine only ever uses one instance, one transcription at a time.
private struct PipeBox: @unchecked Sendable { let pipe: WhisperKit }

enum WhisperKitEngineError: LocalizedError {
    case download(String)
    var errorDescription: String? {
        switch self {
        case .download(let message): "The WhisperKit download did not finish: \(message)"
        }
    }
}

/// The real downloader: WhisperKit's Hugging Face client, fetching only the turbo variant.
struct HubModelDownloader: WhisperKitModelDownloader {
    func download(into store: WhisperKitModelStore, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await WhisperKit.download(variant: WhisperKitModelStore.variant, downloadBase: store.root,
                                          from: WhisperKitModelStore.repo) { update in
            progress(update.fractionCompleted)
        }
    }
}
