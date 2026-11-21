import AVFoundation
import Foundation
import Observation
import ZeusCore

/// Writes 16 kHz mono samples to a temporary WAV for the command line speech tools.
enum TemporaryWAV {
    static func write(_ samples: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AudioSamples.buffer(samples) else { throw TranscriptionError.noSpeech }
        try file.write(from: buffer)
        return url
    }
}

/// whisper.cpp through its `whisper-cli` tool (Homebrew: `brew install whisper-cpp`). Models are
/// plain ggml files in Application Support/Zeus/WhisperModels, downloaded when asked.
final class WhisperCppEngine: TranscriptionEngine, @unchecked Sendable {
    let kind = TranscriptionEngineKind.whisper

    struct Model: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let megabytes: Int
        var file: String { "ggml-\(id).bin" }
        var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)")! }
    }

    static let models = [
        Model(id: "base.en", title: "Base, English", megabytes: 148),
        Model(id: "small", title: "Small, many languages", megabytes: 488),
        Model(id: "large-v3-turbo-q5_0", title: "Large v3 turbo, many languages", megabytes: 574),
    ]

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/WhisperModels", isDirectory: true)
    }

    static var binary: String? {
        ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli", "/opt/homebrew/bin/whisper-cpp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var selectedModelID: String {
        get { UserDefaults.standard.string(forKey: "dictation.whisperModel") ?? models[0].id }
        set { UserDefaults.standard.set(newValue, forKey: "dictation.whisperModel") }
    }

    static func modelURL(_ model: Model) -> URL { modelsDirectory.appendingPathComponent(model.file) }
    static func isDownloaded(_ model: Model) -> Bool { FileManager.default.fileExists(atPath: modelURL(model).path) }

    static var selectedModel: Model { models.first { $0.id == selectedModelID } ?? models[0] }

    /// Any downloaded model file counts, so a hand-placed `ggml-*.bin` also works.
    var isDownloaded: Bool { Self.binary != nil && Self.isDownloaded(Self.selectedModel) }

    func availability() async -> EngineAvailability {
        guard Self.binary != nil else { return .unavailable("whisper.cpp is not installed. Run: brew install whisper-cpp") }
        return Self.isDownloaded(Self.selectedModel) ? .ready : .notDownloaded
    }

    func prepare(progress: (@Sendable (Double) -> Void)?) async throws {
        try await WhisperModelDownloader.download(Self.selectedModel, progress: progress)
    }

    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.noSpeech }
        guard let binary = Self.binary, Self.isDownloaded(Self.selectedModel) else { throw TranscriptionError.notReady(.whisper) }
        let model = Self.modelURL(Self.selectedModel).path
        let wav = try TemporaryWAV.write(samples)
        defer { try? FileManager.default.removeItem(at: wav) }
        let english = Self.selectedModel.id.hasSuffix(".en")
        let languageCode = DictationLanguage.engineLanguageCode(for: language)
        guard !english || languageCode == nil || languageCode == "en" else {
            throw TranscriptionError.notReady(.whisper)
        }
        let arguments = ["-m", model, "-f", wav.path, "-nt", "-np", "-l", english ? "en" : (languageCode ?? "auto")]
        let prompt = DictationVocabularyPrompt.whisperPrompt(terms: hints)
        return try await WhisperPromptRecovery.transcribe(sentPrompt: prompt) { attempt in
            let args = arguments + (attempt.prompt.isEmpty ? [] : ["--prompt", attempt.prompt])
            let result = await Task.detached { LocalPython.run(binary, args, timeout: 120) }.value
            guard result.status == 0 else { throw TranscriptionError.notReady(.whisper) }
            return Self.clean(result.output)
        }
    }

    /// whisper.cpp prints bracketed non-speech marks such as [BLANK_AUDIO]; drop them.
    static func clean(_ output: String) -> String {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.replacingOccurrences(of: #"\[[A-Z_ ]+\]|\([a-z ]+\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Downloads a ggml model with progress. Nothing else leaves the Mac.
enum WhisperModelDownloader {
    static func download(_ model: WhisperCppEngine.Model, progress: (@Sendable (Double) -> Void)?) async throws {
        try FileManager.default.createDirectory(at: WhisperCppEngine.modelsDirectory, withIntermediateDirectories: true)
        let target = WhisperCppEngine.modelURL(model)
        let partial = target.appendingPathExtension("partial")
        guard let known = PinnedModelBytes.whisperKnownBytes(id: model.id) else { throw DownloadCapExceeded() }
        let maximum = PinnedModelBytes.cap(known)
        let outcome = await DownloadRunner.run(kind: .model, clock: { Date().timeIntervalSinceReferenceDate }, partials: { [partial] }) {
            let transfer = DownloadTransferGuard(maximumBytes: maximum, allowedHosts: PinnedDownloadHosts.whisper, report: progress)
            transfer.destination = partial
            let session = URLSession(configuration: .default, delegate: transfer, delegateQueue: nil)
            try await withTaskCancellationHandler {
                do {
                    let (_, response) = try await session.download(from: model.url)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? transfer.statusCode ?? 0
                    guard code == 200 else { throw URLError(.badServerResponse) }
                } catch is DownloadCapExceeded {
                    throw DownloadCapExceeded()
                } catch {
                    if transfer.keptURL == nil {
                        if transfer.stopped { throw DownloadCapExceeded() }
                        throw error
                    }
                }
                if transfer.stopped || transfer.keptURL == nil { throw DownloadCapExceeded() }
                let kept = transfer.keptURL!
                let size = ((try? FileManager.default.attributesOfItem(atPath: kept.path))?[.size] as? NSNumber)?.int64Value ?? 0
                if size > maximum || (ArchiveUnpackCap.isArchive(model.file) && ArchiveUnpackCap.exceeds(producedBytes: size, maximumBytes: maximum)) {
                    throw DownloadCapExceeded()
                }
                session.finishTasksAndInvalidate()
            } onCancel: {
                session.invalidateAndCancel()
            }
        }
        switch outcome {
        case .finished:
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: partial, to: target)
            progress?(1)
        case .tookTooLong:
            throw DownloadTookTooLong()
        case .cancelled:
            throw CancellationError()
        case .capped:
            throw DownloadCapExceeded()
        case .failed(let message):
            throw NSError(domain: "Zeus", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

/// faster-whisper in the private Python environment (set up from Settings, once). CTranslate2 has
/// no Apple GPU or Neural Engine path, so it runs on the CPU: slower on a Mac than the others.
final class FasterWhisperEngine: TranscriptionEngine, @unchecked Sendable {
    let kind = TranscriptionEngineKind.fasterWhisper

    static var modelName: String {
        get { UserDefaults.standard.string(forKey: "dictation.fasterWhisperModel") ?? "base" }
        set { UserDefaults.standard.set(newValue, forKey: "dictation.fasterWhisperModel") }
    }
    static let modelNames = ["base", "small", "large-v3-turbo"]

    private static let script = """
    import sys
    from faster_whisper import WhisperModel
    path, model, prompt, language, skip_vad = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] == "1"
    language = language or None
    segments, _ = WhisperModel(model, device="cpu", compute_type="int8").transcribe(path, language=language, initial_prompt=prompt or None, vad_filter=not skip_vad)
    print(" ".join(s.text.strip() for s in segments))
    """

    /// Cheap synchronous check: the module's files exist (no interpreter is started).
    static var isSetUp: Bool {
        let lib = LocalPython.venv.appendingPathComponent("lib")
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: lib.path) else { return false }
        return versions.contains { FileManager.default.fileExists(atPath: lib.appendingPathComponent("\($0)/site-packages/faster_whisper").path) }
    }

    var isDownloaded: Bool { Self.isSetUp }

    func availability() async -> EngineAvailability { Self.isSetUp ? .ready : .notDownloaded }

    func prepare(progress: (@Sendable (Double) -> Void)?) async throws {
        progress?(0.05)
        let pythonRoot = LocalPython.root
        let tree = LocalPython.venv
        let rootExisted = FileManager.default.fileExists(atPath: pythonRoot.path)
        let treeExisted = FileManager.default.fileExists(atPath: tree.path)
        let before = treeExisted ? InstallFootprint.snapshot(tree) : []
        let beforeSizes: [String: Int64]
        if treeExisted {
            guard let sizes = InstallFootprint.sizeSnapshot(tree) else {
                throw NSError(domain: "Zeus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not measure the Python environment."])
            }
            beforeSizes = sizes
        } else {
            beforeSizes = [:]
        }
        let gate = InstallSettlement()
        let worker = Task.detached {
            let failure = LocalPython.install(["faster-whisper"])
            gate.settle(failure)
            return failure
        }
        let outcome = await DownloadRunner.run(kind: .model, clock: { Date().timeIntervalSinceReferenceDate }, partials: {
            // Wait until pip has exited, then delete every path this setup added.
            _ = gate.wait()
            return InstallFootprint.removals(root: pythonRoot, rootExisted: rootExisted, tree: tree, treeExisted: treeExisted, before: before)
        }) {
            let failure = await worker.value
            if let failure { throw NSError(domain: "Zeus", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
            guard let produced = InstallFootprint.producedBytes(tree: tree, treeExisted: treeExisted, before: beforeSizes) else {
                throw NSError(domain: "Zeus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not measure the Python environment."])
            }
            if ArchiveUnpackCap.exceeds(producedBytes: produced, maximumBytes: FasterWhisperUnpack.maximumBytes) {
                throw DownloadCapExceeded()
            }
        }
        switch outcome {
        case .finished: progress?(1)
        case .tookTooLong: throw DownloadTookTooLong()
        case .cancelled: throw CancellationError()
        case .capped: throw DownloadCapExceeded()
        case .failed(let message): throw NSError(domain: "Zeus", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.noSpeech }
        guard Self.isSetUp else { throw TranscriptionError.notReady(.fasterWhisper) }
        let wav = try TemporaryWAV.write(samples)
        defer { try? FileManager.default.removeItem(at: wav) }
        let languageCode = DictationLanguage.engineLanguageCode(for: language) ?? ""
        let model = Self.modelName
        return try await WhisperPromptRecovery.transcribe(sentPrompt: DictationVocabularyPrompt.whisperPrompt(terms: hints)) { attempt in
            let args = ["-I", "-c", Self.script, wav.path, model, attempt.prompt, languageCode,
                        attempt.skipVoiceActivityDetection ? "1" : "0"]
            let result = await Task.detached { LocalPython.run(LocalPython.python.path, args, timeout: 300) }.value
            guard result.status == 0 else { throw TranscriptionError.notReady(.fasterWhisper) }
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// Pip finishes on a detached task. Cleanup waits here so a cap cannot delete files before they exist,
/// and cannot return while pip is still writing them.
private final class InstallSettlement: @unchecked Sendable {
    private let condition = NSCondition()
    private var ready = false
    private var failure: String?

    func settle(_ failure: String?) {
        condition.lock()
        self.failure = failure
        ready = true
        condition.broadcast()
        condition.unlock()
    }

    func wait() -> String? {
        condition.lock()
        while !ready { condition.wait() }
        let failure = self.failure
        condition.unlock()
        return failure
    }
}
