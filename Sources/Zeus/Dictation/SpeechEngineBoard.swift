import Foundation
import Observation
import ZeusCore

/// Every engine's state on this Mac, for the Engine picker in Settings › Murmure and Dictation,
/// and the one-click actions behind it. Downloads go through each engine's existing path
/// (FluidAudio for Parakeet, the ggml downloader for whisper.cpp, the private Python setup for
/// faster-whisper, WhisperKit's own download, macOS's asset install for SpeechAnalyzer).
@MainActor
@Observable
final class SpeechEngineBoard {
    static let shared = SpeechEngineBoard()

    private(set) var states: [TranscriptionEngineKind: EngineAvailability] = [:]
    /// 0…1 while an engine downloads or sets up.
    var progress: [TranscriptionEngineKind: Double] = [:]
    /// The last problem or result worth a line in Settings (never a key).
    var message: String?
    /// The cloud engine whose key field is open.
    var editingKey: TranscriptionEngineKind?
    var keyDraft = ""

    private var controller: DictationController? { DictationHub.shared.controller }

    /// What the picker shows: live progress first, then the last check.
    func availability(_ kind: TranscriptionEngineKind) -> EngineAvailability {
        if kind == .parakeet, let fraction = SpeechEngineStatus.shared.progress { return .downloading(fraction) }
        if kind == .parakeet, SpeechEngineStatus.shared.downloaded { return .ready }
        if let fraction = progress[kind] { return .downloading(fraction) }
        if let state = states[kind] { return state }
        switch kind {
        case .apple: return .ready
        case .elevenLabs, .openAI: return CloudKeys.has(kind) ? .ready : .needsKey
        case .appleAnalyzer: return AppleAnalyzerEngine.isSupportedOS ? .notDownloaded : .needsNewerMacOS
        default: return .notDownloaded
        }
    }

    /// Picker label: an engine that is not ready yet says so, so choosing it is never a silent dead end.
    func pickerTitle(_ kind: TranscriptionEngineKind) -> String {
        if kind == DictationSettings.shared.engine { return kind.title }
        if case .ready = availability(kind) { return kind.title }
        return "\(kind.title) (set up first)"
    }

    /// Applies a picker choice. An engine that is not ready is not selected; the reason shows in `message`.
    func choose(pickerTitle title: String) {
        guard let kind = TranscriptionEngineKind.allCases.first(where: { pickerTitle($0) == title }) else { return }
        if kind == DictationSettings.shared.engine { return }
        if case .ready = availability(kind) {
            DictationSettings.shared.engine = kind
            message = nil
        } else {
            message = "\(kind.title) is not ready. Download it or add its key on the Dictation page, then pick it."
        }
    }

    func refresh() async {
        guard let controller else { return }
        var fresh: [TranscriptionEngineKind: EngineAvailability] = [:]
        for kind in TranscriptionEngineKind.allCases {
            fresh[kind] = await controller.engine(kind).availability()
        }
        states = fresh
    }

    /// The one-click action for `kind`'s row.
    func perform(_ action: EngineStatusLine.Action, for kind: TranscriptionEngineKind) {
        switch action {
        case .use, .inUse: DictationSettings.shared.engine = kind
        case .download: download(kind)
        case .addKey:
            editingKey = kind
            keyDraft = ""
        case .cancel: cancelDownload(kind)
        case .none: break
        }
    }

    /// Stops a WhisperKit download; the partial files stay and the next Download resumes them.
    func cancelDownload(_ kind: TranscriptionEngineKind) {
        guard kind == .whisperKit, let engine = controller?.engine(kind) as? WhisperKitEngine else { return }
        engine.cancelDownload()
        message = "Download cancelled."
    }

    func saveKey() {
        guard let kind = editingKey else { return }
        CloudKeys.save(keyDraft, for: kind)
        keyDraft = ""
        editingKey = nil
        Task { await refresh() }
    }

    func download(_ kind: TranscriptionEngineKind) {
        guard let controller, progress[kind] == nil else { return }
        message = nil
        switch kind {
        case .parakeet:
            controller.prepareModel()
            return
        case .whisper:
            let model = WhisperCppEngine.selectedModel
            progress[kind] = 0
            run(kind, success: "\(model.title) is ready.", failure: "The download did not finish. Check your connection and try again.") {
                try await WhisperModelDownloader.download(model) { fraction in
                    Task { @MainActor in SpeechEngineBoard.shared.progress[kind] = fraction }
                }
            }
        case .fasterWhisper:
            progress[kind] = 0.05
            message = "Setting up faster-whisper. This takes a few minutes the first time."
            run(kind, success: "faster-whisper is ready. Its model downloads the first time you dictate.", failure: nil) {
                try await FasterWhisperEngine().prepare(progress: nil)
            }
        default:
            let engine = controller.engine(kind)
            progress[kind] = 0
            run(kind, success: kind == .whisperKit ? "Whisper turbo is ready." : "\(kind.title) is ready.", failure: nil) {
                try await engine.prepare { fraction in
                    Task { @MainActor in SpeechEngineBoard.shared.progress[kind] = fraction }
                }
            }
        }
    }

    private func run(_ kind: TranscriptionEngineKind, success: String, failure: String?,
                     _ work: @escaping @Sendable () async throws -> Void) {
        Task { @MainActor in
            do {
                try await work()
                message = success
            } catch is CancellationError {
                message = "Download cancelled."
            } catch {
                message = failure ?? error.localizedDescription
            }
            progress[kind] = nil
            await refresh()
        }
    }
}
