import Foundation
import NaturalLanguage
import Speech
import Translation
import ZeusCore

/// Zeus's own speech engines for live captions: Parakeet v3 (25 languages, on the Neural Engine)
/// when it is downloaded, Apple's on-device recognizer otherwise and for any language Parakeet
/// does not cover once the language is known.
final class PolyglotRecognizer: PolyglotRecognizing, @unchecked Sendable {
    private let parakeet: ParakeetEngine
    private let useParakeet: Bool

    init(parakeet: ParakeetEngine, useParakeet: Bool) {
        self.parakeet = parakeet
        self.useParakeet = useParakeet
    }

    var engineName: String { useParakeet ? "Parakeet v3" : "Apple on-device" }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        let known = language.map(PolyglotLanguage.base)
        let covered = known.map { PolyglotLanguage.parakeetLanguages.contains($0) } ?? true
        if useParakeet, covered {
            // No script hint: v3 detects the language itself, so mixed-language meetings work.
            return try await parakeet.transcribe(samples: samples, hints: [], language: nil)
        }
        return try await Self.transcribeOnDevice(samples: samples, localeIdentifier: known.flatMap(Self.locale(for:)))
    }

    /// Why Apple's recognizer cannot be used for captions right now, or nil when it can run fully on this Mac.
    /// Captions audio never goes to Apple's servers under the "Apple on-device" label.
    static func appleOnDeviceProblem() -> String? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return "Speech Recognition is off for Zeus, so Polyglot has no on-device engine. Turn it on in System Settings, Privacy and Security, or download Parakeet."
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            return "This Mac has no on-device speech recognition for your language. Polyglot will not send audio to Apple's servers. Download Parakeet to use captions."
        }
        return nil
    }

    /// Apple's recognizer with on-device recognition required: unsupported locales fail instead of falling back to servers.
    private static func transcribeOnDevice(samples: [Float], localeIdentifier: String?) async throws -> String {
        let recognizer = localeIdentifier.flatMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            ?? SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw PolyglotRecognizerError.onDeviceUnavailable
        }
        guard !samples.isEmpty, let buffer = AudioSamples.buffer(samples) else { return "" }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = true
        request.append(buffer)
        request.endAudio()
        let pending = PolyglotPendingRecognition()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                guard pending.install(continuation) else { return }
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        pending.finish(.success(result.bestTranscription.formattedString))
                    } else if let error {
                        pending.finish(.failure(error))
                    }
                }
                pending.attach(task)
                // A recognizer that never answers must not hold the caption worker (and Stop) forever.
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                    pending.finish(.failure(PolyglotRecognizerError.timedOut))
                }
            }
        } onCancel: {
            pending.finish(.failure(CancellationError()))
        }
    }

    /// "ja" to the first Apple recognizer locale for Japanese ("ja-JP"); nil when none, so Apple uses the Mac's language.
    static func locale(for base: String) -> String? {
        let match = SFSpeechRecognizer.supportedLocales().first { $0.language.languageCode?.identifier == base.split(separator: "-").first.map(String.init) }
        return match?.identifier
    }
}

enum PolyglotRecognizerError: LocalizedError {
    case onDeviceUnavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable: "on-device recognition is not available for this language, so it was not sent to Apple's servers."
        case .timedOut: "the on-device recognizer did not answer in time."
        }
    }
}

/// One recognition request in flight: resumes its continuation exactly once (result, error, timeout or
/// cancellation) and cancels the recognizer's task when it ends early.
private final class PolyglotPendingRecognition: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var outcome: Result<String, Error>?

    /// False when it already ended (cancelled before it began); the continuation is resumed here in that case.
    func install(_ continuation: CheckedContinuation<String, Error>) -> Bool {
        let early: Result<String, Error>? = lock.withLock {
            if outcome == nil { self.continuation = continuation }
            return outcome
        }
        guard let early else { return true }
        continuation.resume(with: early)
        return false
    }

    func attach(_ task: SFSpeechRecognitionTask) {
        let stale: Bool = lock.withLock {
            if outcome == nil { self.task = task }
            return outcome != nil
        }
        if stale { task.cancel() }
    }

    func finish(_ result: Result<String, Error>) {
        let (waiting, running): (CheckedContinuation<String, Error>?, SFSpeechRecognitionTask?) = lock.withLock {
            guard outcome == nil else { return (nil, nil) }
            outcome = result
            defer { continuation = nil; task = nil }
            return (continuation, task)
        }
        running?.cancel()
        waiting?.resume(with: result)
    }
}

/// Names the language of a transcript line with the system's language recognizer.
struct PolyglotNLDetector: PolyglotLanguageDetecting {
    func detect(_ text: String) -> (code: String, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first else { return nil }
        return (best.key.rawValue, best.value)
    }
}

/// Apple's on-device Translation framework. The programmatic session (`TranslationSession(installedSource:target:)`)
/// needs macOS 26 and installed language packs; a pack that is not installed is reported, never fetched silently.
actor PolyglotAppleTranslator: PolyglotTranslating {
    func status(from source: String, to target: String) async -> PolyglotPackStatus {
        guard #available(macOS 26.0, *) else { return .requiresNewerSystem }
        let availability = LanguageAvailability()
        switch await availability.status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target)) {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    func translate(_ requests: [PolyglotTranslationRequest], from source: String, to target: String) async throws -> [String] {
        guard #available(macOS 26.0, *) else { return requests.map { _ in "" } }
        let session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
        let responses = try await session.translations(from: requests.map {
            TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id))
        })
        let byID = Dictionary(responses.compactMap { response in
            response.clientIdentifier.map { ($0, response.targetText) }
        }, uniquingKeysWith: { first, _ in first })
        // A request the translator skipped answers with nothing (the line stays as heard), never its own text as a "translation".
        return requests.map { byID[String($0.id)] ?? "" }
    }
}
