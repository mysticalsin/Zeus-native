import AVFoundation
import FluidAudio
import Foundation
import Speech
import ZeusCore

/// Parakeet TDT 0.6b v3 through FluidAudio, on the Neural Engine. The model (about 480 MB)
/// downloads once into ~/Library/Application Support/FluidAudio and loads in under a second.
/// Parakeet Ultra (Moondream's post-training of v3, same tokenizer and decoder contract) runs
/// through the very same FluidAudio path with `AsrModelVersion.ultra`.
final class ParakeetEngine: TranscriptionEngine, @unchecked Sendable {
    let kind: TranscriptionEngineKind
    private let version: AsrModelVersion
    private let lock = NSLock()
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?
    private var progress: Double?

    init(_ kind: TranscriptionEngineKind = .parakeet) {
        self.kind = kind
        version = kind == .parakeetUltra ? .ultra : .v3
    }

    private var modelDirectory: URL { AsrModels.defaultCacheDirectory(for: version) }

    var isDownloaded: Bool { AsrModels.modelsExist(at: modelDirectory, version: version) }

    func availability() async -> EngineAvailability {
        let (loaded, fraction) = lock.withLock { (manager != nil, progress) }
        if loaded { return .ready }
        if let fraction { return .downloading(fraction) }
        // Downloaded but not loaded yet still counts as ready: loading takes about half a second.
        return isDownloaded ? .ready : .notDownloaded
    }

    func prepare(progress report: (@Sendable (Double) -> Void)?) async throws {
        _ = try await loadedManager(progress: report)
    }

    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.noSpeech }
        let manager = try await loadedManager(progress: nil)
        var state = TdtDecoderState.make()
        let code = DictationLanguage.engineLanguageCode(for: language)
        let scriptHint = code.flatMap(Language.init(rawValue:))
        return try await manager.transcribe(samples, decoderState: &state, language: scriptHint).text
    }

    private func loadedManager(progress report: (@Sendable (Double) -> Void)?) async throws -> AsrManager {
        let task: Task<AsrManager, Error> = lock.withLock {
            if let manager { return Task { manager } }
            if let loading { return loading }
            let downloading = !isDownloaded
            if downloading { progress = 0 }
            let task = Task { [self] () throws -> AsrManager in
                let models = try await AsrModels.downloadAndLoad(version: self.version) { update in
                    self.lock.withLock { self.progress = update.fractionCompleted }
                    report?(update.fractionCompleted)
                }
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                return manager
            }
            loading = task
            return task
        }
        do {
            let manager = try await task.value
            lock.withLock {
                self.manager = manager
                loading = nil
                progress = nil
            }
            return manager
        } catch {
            lock.withLock {
                loading = nil
                progress = nil
            }
            throw error
        }
    }
}

/// Apple's on-device recognizer over recorded samples. Always ready, so it is the fallback.
final class AppleSpeechEngine: TranscriptionEngine, @unchecked Sendable {
    let kind = TranscriptionEngineKind.apple
    private let defaultLocale: Locale

    init(locale: Locale = .current) {
        defaultLocale = locale
    }

    private func recognizer(language: String?) -> SFSpeechRecognizer? {
        if let language { return SFSpeechRecognizer(locale: Locale(identifier: language)) }
        return SFSpeechRecognizer(locale: defaultLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Raised instead of sending audio to Apple's servers under an "on-device" label.
    struct OnDeviceUnavailable: LocalizedError {
        var errorDescription: String? {
            "On-device speech recognition isn't available for this language, so nothing was sent to Apple. Pick another language or engine."
        }
    }

    func availability() async -> EngineAvailability {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return .unavailable("Speech Recognition is not allowed.") }
        guard let recognizer = recognizer(language: nil), recognizer.isAvailable else {
            return .unavailable("Apple speech recognition is unavailable.")
        }
        return recognizer.supportsOnDeviceRecognition ? .ready : .unavailable("On-device speech recognition isn't available for this language.")
    }

    func prepare(progress: (@Sendable (Double) -> Void)?) async throws {}

    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        guard let recognizer = recognizer(language: language), recognizer.isAvailable else {
            throw TranscriptionError.notReady(.apple)
        }
        // "Apple on-device" means on-device: fail closed rather than fall back to servers.
        guard recognizer.supportsOnDeviceRecognition else { throw OnDeviceUnavailable() }
        guard !samples.isEmpty, let buffer = AudioSamples.buffer(samples) else { throw TranscriptionError.noSpeech }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.addsPunctuation = true
        request.contextualStrings = hints
        request.requiresOnDeviceRecognition = true
        request.append(buffer)
        request.endAudio()
        let run = AppleRecognitionRun()
        // Generous bound: a recognizer that never answers must not hang the caller forever.
        let timeout = max(30.0, Double(samples.count) / 16_000 * 3)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                run.begin(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        run.finish(.success(result.bestTranscription.formattedString))
                    } else if let error {
                        run.finish(.failure(error))
                    }
                }
                run.attach(task)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    run.finish(.failure(AppleRecognitionTimedOut()))
                }
            }
        } onCancel: {
            run.finish(.failure(CancellationError()))
        }
    }
}

struct AppleRecognitionTimedOut: LocalizedError {
    var errorDescription: String? { "Apple speech recognition did not answer in time." }
}

/// One recognition request: the first of result, error, timeout and cancellation resumes the
/// continuation exactly once, and the recognition task is cancelled with it.
private final class AppleRecognitionRun: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var done = false

    func begin(_ continuation: CheckedContinuation<String, Error>) {
        let alreadyDone = lock.withLock { () -> Bool in
            if done { return true }
            self.continuation = continuation
            return false
        }
        if alreadyDone { continuation.resume(throwing: CancellationError()) }
    }

    func attach(_ task: SFSpeechRecognitionTask) {
        let lost = lock.withLock { () -> Bool in
            if done { return true }
            self.task = task
            return false
        }
        if lost { task.cancel() }
    }

    func finish(_ result: Result<String, Error>) {
        let (pending, running) = lock.withLock { () -> (CheckedContinuation<String, Error>?, SFSpeechRecognitionTask?) in
            guard !done else { return (nil, nil) }
            done = true
            defer { continuation = nil; task = nil }
            return (continuation, task)
        }
        running?.cancel()
        pending?.resume(with: result)
    }
}

/// 16 kHz mono Float audio, the format every engine takes.
enum AudioSamples {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    /// Why a file could not be turned into samples (never a silent empty result).
    struct LoadError: LocalizedError {
        let errorDescription: String?
    }

    /// Reads any audio or movie file into 16 kHz mono samples, one chunk at a time so a long
    /// recording never needs one buffer for the whole file.
    static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0 else { throw LoadError(errorDescription: "That file has no audio.") }
        guard AVAudioConverter(from: format, to: Self.format) != nil else {
            throw LoadError(errorDescription: "That audio format can't be converted.")
        }
        let chunk: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw LoadError(errorDescription: "Not enough memory to read the file.")
        }
        let resampler = Resampler(from: format)
        var samples: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            if buffer.frameLength == 0 { break }
            samples += try resampler.convertChecked(buffer, final: file.framePosition >= file.length)
        }
        guard !samples.isEmpty else { throw LoadError(errorDescription: "That file has no audio.") }
        return samples
    }

    /// Converts microphone buffers to 16 kHz mono as they arrive.
    final class Resampler: @unchecked Sendable {
        private let converter: AVAudioConverter?
        private let ratio: Double

        init(from input: AVAudioFormat) {
            converter = AVAudioConverter(from: input, to: AudioSamples.format)
            ratio = AudioSamples.format.sampleRate / input.sampleRate
        }

        /// `final` flushes the converter; leave it off between microphone buffers. A failed buffer
        /// is dropped here: the live path has no place to report it, files use `convertChecked`.
        func convert(_ buffer: AVAudioPCMBuffer, final: Bool = false) -> [Float] {
            (try? convertChecked(buffer, final: final)) ?? []
        }

        /// Like `convert`, but a converter failure throws instead of returning an empty chunk, so a
        /// file transcript is never built from a partial conversion.
        func convertChecked(_ buffer: AVAudioPCMBuffer, final: Bool = false) throws -> [Float] {
            guard buffer.frameLength > 0 else { return [] }
            guard let converter else { throw LoadError(errorDescription: "That audio format can't be converted.") }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: AudioSamples.format, frameCapacity: capacity) else {
                throw LoadError(errorDescription: "Not enough memory to convert the file.")
            }
            var fed = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if fed {
                    inputStatus.pointee = final ? .endOfStream : .noDataNow
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if status == .error || error != nil {
                throw LoadError(errorDescription: "Converting the audio failed: \(error?.localizedDescription ?? "unknown error"). Nothing was transcribed.")
            }
            guard let channel = output.floatChannelData?[0] else {
                throw LoadError(errorDescription: "Converting the audio failed. Nothing was transcribed.")
            }
            return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
    }
}
