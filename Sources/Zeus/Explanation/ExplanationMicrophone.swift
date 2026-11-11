import AVFoundation
import Foundation
import Observation
import Speech
import ZeusCore

enum ExplanationMicrophoneError: Error, Equatable {
    case busy, microphoneDenied, speechDenied, engineNotReady, cacheOnlyEngineRequired, noSpeech
    case configurationChanged, recordingLimit, staleTurn
}

enum ExplanationInputSelection: Sendable {
    case appleOnDevice
    /// Requires the explicit cache-only capability below. Installed files or an
    /// ordinary engine's `.ready` status alone never authorize lazy preparation.
    case installedLocal(any TranscriptionEngine)
}

protocol ExplanationCacheOnlyTranscribing: TranscriptionEngine {
    func cacheOnlyAvailability() async -> EngineAvailability
    func transcribeCached(samples: [Float], hints: [String], language: String?) async throws -> String
}

extension WhisperKitEngine: ExplanationCacheOnlyTranscribing {
    func cacheOnlyAvailability() async -> EngineAvailability { availabilityWithoutLoading() }
    func transcribeCached(samples: [Float], hints: [String], language: String?) async throws -> String {
        try await transcribeWithoutLoading(samples: samples, hints: hints, language: language)
    }
}

@MainActor
protocol ExplanationInputPermissions: AnyObject {
    func microphone() async -> Bool
    func speechRecognition() async -> Bool
}

@MainActor
private final class NativeExplanationInputPermissions: ExplanationInputPermissions {
    func microphone() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    func speechRecognition() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            return await SystemAuthorization.requestSpeechRecognition() == .authorized
        }
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
}

@MainActor
protocol ExplanationInputCapturing: AnyObject {
    var onPartial: ((UInt64, String) -> Void)? { get set }
    var onLevel: ((UInt64, Double) -> Void)? { get set }
    var onFailure: ((UInt64, SpeechInput.CaptureFailure) -> Void)? { get set }
    func start(generation: UInt64, appleRecognition: Bool, deviceUID: String?, locale: String?, hints: [String]) throws
    func stop() async -> String
    func takeSamples() -> [Float]
    func cancel()
}

@MainActor
private final class NativeExplanationInputCapture: ExplanationInputCapturing {
    var onPartial: ((UInt64, String) -> Void)?
    var onLevel: ((UInt64, Double) -> Void)?
    var onFailure: ((UInt64, SpeechInput.CaptureFailure) -> Void)?
    private let speech = SpeechInput()
    private var generation: UInt64 = 0
    private var updatesTask: Task<Void, Never>?

    func start(generation: UInt64, appleRecognition: Bool, deviceUID: String?, locale: String?, hints: [String]) throws {
        self.generation = generation
        speech.recognizes = appleRecognition
        speech.allowServerRecognition = false
        speech.recordsSamples = !appleRecognition
        speech.deviceUID = deviceUID
        speech.contextualStrings = Array(hints.prefix(128)).map { String($0.prefix(128)) }
        if appleRecognition, !speech.configure(localeIdentifier: locale) { throw SpeechInput.InputError.recognizerUnavailable }
        let updates = ExplanationInputUpdates()
        speech.onIdentifiedPartial = { _, origin, text in
            guard origin == generation else { return }
            updates.partial(text)
        }
        speech.onLevel = { level in updates.level(level) }
        speech.onCaptureFailure = { [weak self] _, origin, failure in
            Task { @MainActor in
                guard let self, self.generation == origin else { return }
                self.onFailure?(origin, failure)
            }
        }
        do { try speech.start(controllerGeneration: generation, capturePolicy: .explanation) }
        catch { cancel(); throw error }
        updatesTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, self.generation == generation else { return }
                let (partial, level) = updates.take()
                if let partial { self.onPartial?(generation, partial) }
                if let level { self.onLevel?(generation, level) }
            }
        }
    }

    func stop() async -> String { await speech.stop() }
    func takeSamples() -> [Float] { speech.takeSamples() }
    func cancel() {
        generation &+= 1
        updatesTask?.cancel(); updatesTask = nil
        speech.onLevel = nil; speech.onIdentifiedPartial = nil; speech.onCaptureFailure = nil
        speech.cancel(); _ = speech.takeSamples()
    }
    isolated deinit { updatesTask?.cancel(); speech.cancel() }
}

/// Latest-value mailbox bounds callback traffic while the main actor is busy.
private final class ExplanationInputUpdates: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?
    private var value: Double?
    func partial(_ text: String) { lock.withLock { self.text = String(text.prefix(16_000)) } }
    func level(_ value: Double) { lock.withLock { self.value = value } }
    func take() -> (String?, Double?) {
        lock.withLock { defer { text = nil; value = nil }; return (text, value) }
    }
}

/// Push-to-talk capture only: no dictation insertion, VoiceTurn execution, screenshots,
/// automatic cloud fallback or model preparation. The owning app arbitrates wake-word
/// listening and other output through the injected acquire/release callbacks.
@MainActor
@Observable
final class ExplanationMicrophone {
    enum State: Equatable { case idle, requestingPermission, listening, transcribing }
    private(set) var state: State = .idle
    private(set) var partial = ""
    private(set) var level = 0.0
    private(set) var problem: ExplanationMicrophoneError?
    private let permissions: any ExplanationInputPermissions
    private let capture: any ExplanationInputCapturing
    private let acquire: () throws -> Void
    private let release: () -> Void
    private var ownsCapture = false
    private var generation: UInt64 = 0
    private var selection: ExplanationInputSelection = .appleOnDevice
    private var locale: String?
    private var hints: [String] = []
    private var limitTask: Task<Void, Never>?
    private var transcription: Task<String, Error>?
    private var transcriptionOwner: UInt64?

    init(permissions: (any ExplanationInputPermissions)? = nil,
         capture: (any ExplanationInputCapturing)? = nil,
         acquire: @escaping () throws -> Void = {}, release: @escaping () -> Void = {}) {
        self.permissions = permissions ?? NativeExplanationInputPermissions()
        self.capture = capture ?? NativeExplanationInputCapture()
        self.acquire = acquire; self.release = release
    }

    /// Called only by an explicit press. Cancel/release while the OS dialog is open
    /// invalidates this generation, so a late permission answer cannot start capture.
    func start(selection: ExplanationInputSelection = .appleOnDevice, deviceUID: String? = nil,
               locale: String? = nil, hints: [String] = []) async throws {
        guard state == .idle, transcription == nil else { throw ExplanationMicrophoneError.busy }
        try Task.checkCancellation()
        generation &+= 1
        let current = generation
        state = .requestingPermission; problem = nil; partial = ""; level = 0
        do {
            let apple: Bool
            switch selection {
            case .appleOnDevice: apple = true
            case .installedLocal(let engine):
                guard !engine.kind.isCloud, let cached = engine as? any ExplanationCacheOnlyTranscribing else {
                    throw ExplanationMicrophoneError.cacheOnlyEngineRequired
                }
                guard await cached.cacheOnlyAvailability() == .ready else { throw ExplanationMicrophoneError.engineNotReady }
                apple = false
            }
            try check(current)
            guard await permissions.microphone() else { throw ExplanationMicrophoneError.microphoneDenied }
            try check(current)
            if apple {
                guard await permissions.speechRecognition() else { throw ExplanationMicrophoneError.speechDenied }
                try check(current)
            }
            try acquire(); ownsCapture = true
            self.selection = selection; self.locale = locale; self.hints = Array(hints.prefix(128)).map { String($0.prefix(128)) }
            capture.onPartial = { [weak self] origin, text in
                guard let self, self.generation == origin, self.state == .listening else { return }
                self.partial = String(text.prefix(16_000))
            }
            capture.onLevel = { [weak self] origin, level in
                guard let self, self.generation == origin, self.state == .listening else { return }
                self.level = level.isFinite ? min(1, max(0, level)) : 0
            }
            capture.onFailure = { [weak self] origin, failure in
                guard let self, self.generation == origin else { return }
                self.cancel()
                self.problem = failure == .configurationChanged ? .configurationChanged : .recordingLimit
            }
            try capture.start(generation: current, appleRecognition: apple, deviceUID: deviceUID, locale: locale, hints: self.hints)
            state = .listening
            limitTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(90)) } catch { return }
                guard let self, self.generation == current else { return }
                self.cancel(); self.problem = .recordingLimit
            }
        } catch {
            if generation == current { cancel(); problem = error as? ExplanationMicrophoneError }
            throw error
        }
    }

    func finish() async throws -> String {
        guard state == .listening else { cancel(); throw ExplanationMicrophoneError.staleTurn }
        let current = generation
        state = .transcribing; limitTask?.cancel(); limitTask = nil
        defer {
            if generation == current {
                capture.cancel(); relinquish(); state = .idle; level = 0
            }
            if transcriptionOwner == current { transcription = nil; transcriptionOwner = nil }
        }
        let live = await capture.stop()
        try check(current)
        let samples = capture.takeSamples()
        capture.cancel(); relinquish()
        let text: String
        switch selection {
        case .appleOnDevice: text = live
        case .installedLocal(let engine):
            guard let cached = engine as? any ExplanationCacheOnlyTranscribing else {
                throw ExplanationMicrophoneError.cacheOnlyEngineRequired
            }
            guard !samples.isEmpty, samples.count <= 90 * 16_000, samples.allSatisfy(\.isFinite) else {
                throw ExplanationMicrophoneError.noSpeech
            }
            let hints = hints, locale = locale
            let work = Task { try await cached.transcribeCached(samples: samples, hints: hints, language: locale) }
            transcription = work; transcriptionOwner = current
            text = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        }
        try check(current)
        let bounded = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16_000))
        guard !bounded.isEmpty else { throw ExplanationMicrophoneError.noSpeech }
        partial = bounded
        return bounded
    }

    func cancel() {
        generation &+= 1
        limitTask?.cancel(); limitTask = nil
        transcription?.cancel() // Keep its slot owned until the real operation unwinds.
        capture.cancel(); relinquish()
        state = .idle; partial = ""; level = 0
    }

    private func check(_ current: UInt64) throws {
        try Task.checkCancellation()
        guard generation == current else { throw ExplanationMicrophoneError.staleTurn }
    }
    private func relinquish() { if ownsCapture { ownsCapture = false; release() } }
    isolated deinit { cancel() }
}
