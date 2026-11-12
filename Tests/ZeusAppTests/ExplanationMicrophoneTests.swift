import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Explanation push-to-talk with synthetic capture")
struct ExplanationMicrophoneTests {
    @MainActor
    private final class Permissions: ExplanationInputPermissions {
        var micAllowed = true, speechAllowed = true
        var micRequests = 0, speechRequests = 0
        var pending: CheckedContinuation<Bool, Never>?
        var holdMic = false
        func microphone() async -> Bool {
            micRequests += 1
            if holdMic { return await withCheckedContinuation { pending = $0 } }
            return micAllowed
        }
        func speechRecognition() async -> Bool { speechRequests += 1; return speechAllowed }
    }

    @MainActor
    private final class Capture: ExplanationInputCapturing {
        var onPartial: ((UInt64, String) -> Void)?
        var onLevel: ((UInt64, Double) -> Void)?
        var onFailure: ((UInt64, SpeechInput.CaptureFailure) -> Void)?
        var generations: [UInt64] = []
        var modes: [Bool] = []
        var cancelled = 0
        var text = "Synthetic speech"
        var samples: [Float] = [0, 0, 0]
        func start(generation: UInt64, appleRecognition: Bool, deviceUID: String?, locale: String?, hints: [String]) throws {
            generations.append(generation); modes.append(appleRecognition)
        }
        func stop() async -> String { text }
        func takeSamples() -> [Float] { defer { samples = [] }; return samples }
        func cancel() { cancelled += 1 }
    }

    private actor Engine: ExplanationCacheOnlyTranscribing {
        nonisolated let kind: TranscriptionEngineKind
        var ready = true
        var preparations = 0
        var calls = 0
        var ordinaryCalls = 0
        var pending: CheckedContinuation<String, Never>?
        var releaseTask: Task<Void, Never>?
        let held: Bool
        init(kind: TranscriptionEngineKind = .whisperKit, held: Bool = false) { self.kind = kind; self.held = held }
        func availability() async -> EngineAvailability { ready ? .ready : .notDownloaded }
        func cacheOnlyAvailability() async -> EngineAvailability { ready ? .ready : .notDownloaded }
        func prepare(progress: (@Sendable (Double) -> Void)?) async throws { preparations += 1 }
        func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
            ordinaryCalls += 1
            return "Ordinary API must not be called"
        }
        func transcribeCached(samples: [Float], hints: [String], language: String?) async throws -> String {
            calls += 1
            if held {
                return await withCheckedContinuation {
                    pending = $0
                    releaseTask = Task {
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                        release()
                    }
                }
            }
            return "Locally transcribed"
        }
        func release() {
            releaseTask?.cancel(); releaseTask = nil
            pending?.resume(returning: "Late old transcript"); pending = nil
        }
        var waiting: Bool { pending != nil }
    }

    private actor UnverifiedEngine: TranscriptionEngine {
        nonisolated let kind: TranscriptionEngineKind
        var calls = 0, preparations = 0
        init(kind: TranscriptionEngineKind) { self.kind = kind }
        func availability() async -> EngineAvailability { .ready }
        func prepare(progress: (@Sendable (Double) -> Void)?) async throws { preparations += 1 }
        func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String { calls += 1; return "Unverified" }
    }

    @Test func localRecognitionRequestsOnlyMicAndNeverPreparesOrFallsBack() async throws {
        let permissions = Permissions(), capture = Capture(), engine = Engine()
        permissions.speechAllowed = false
        var acquired = 0, released = 0
        let microphone = ExplanationMicrophone(permissions: permissions, capture: capture,
                                              acquire: { acquired += 1 }, release: { released += 1 })
        try await microphone.start(selection: .installedLocal(engine))
        #expect(permissions.micRequests == 1 && permissions.speechRequests == 0)
        #expect(capture.modes == [false])
        #expect(try await microphone.finish() == "Locally transcribed")
        let preparations = await engine.preparations, calls = await engine.calls
        #expect(preparations == 0 && calls == 1)
        #expect(await engine.ordinaryCalls == 0)
        #expect(acquired == 1 && released == 1)
        #expect(microphone.state == .idle)
    }

    @Test func appleRecognitionRequiresBothPermissionsBeforeCapture() async throws {
        let permissions = Permissions(), capture = Capture()
        permissions.speechAllowed = false
        var acquired = 0
        let microphone = ExplanationMicrophone(permissions: permissions, capture: capture, acquire: { acquired += 1 })
        await #expect(throws: ExplanationMicrophoneError.speechDenied) { try await microphone.start() }
        #expect(permissions.micRequests == 1 && permissions.speechRequests == 1)
        #expect(capture.generations.isEmpty && acquired == 0)
        #expect(microphone.state == .idle)
        permissions.speechAllowed = true
        try await microphone.start()
        #expect(capture.modes == [true])
        #expect(try await microphone.finish() == "Synthetic speech")
    }

    @Test func releaseDuringPermissionDialogCannotStartAfterLateApproval() async throws {
        let permissions = Permissions(), capture = Capture()
        permissions.holdMic = true
        let microphone = ExplanationMicrophone(permissions: permissions, capture: capture)
        let work = Task { try await microphone.start() }
        defer {
            work.cancel(); microphone.cancel()
            permissions.pending?.resume(returning: false); permissions.pending = nil
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while permissions.pending == nil, ContinuousClock.now < deadline { await Task.yield() }
        let continuation = try #require(permissions.pending)
        permissions.pending = nil
        microphone.cancel()
        continuation.resume(returning: true)
        do { try await work.value; Issue.record("Late permission started capture") }
        catch let error as ExplanationMicrophoneError { #expect(error == .staleTurn) }
        #expect(capture.generations.isEmpty)
        #expect(permissions.speechRequests == 0)
    }

    @Test func stalePartialsAndDeviceChangesCannotMutateReplacementTurn() async throws {
        let capture = Capture()
        var released = 0
        let microphone = ExplanationMicrophone(permissions: Permissions(), capture: capture, release: { released += 1 })
        try await microphone.start()
        let oldGeneration = try #require(capture.generations.last)
        let stale = capture.onPartial, staleFailure = capture.onFailure
        microphone.cancel()
        try await microphone.start()
        let current = try #require(capture.generations.last)
        stale?(oldGeneration, "Wrong turn"); staleFailure?(oldGeneration, .configurationChanged)
        #expect(microphone.partial.isEmpty && microphone.state == .listening)
        capture.onPartial?(current, "Current turn")
        capture.onLevel?(current, .infinity)
        #expect(microphone.partial == "Current turn" && microphone.level == 0)
        capture.onFailure?(current, .configurationChanged)
        #expect(microphone.state == .idle && microphone.problem == .configurationChanged)
        #expect(released == 2)
    }

    @Test func unsafeOrCloudEngineIsRejectedBeforePermissionsAndCapture() async throws {
        for kind: TranscriptionEngineKind in [.whisperKit, .parakeet, .openAI, .elevenLabs] {
            let permissions = Permissions(), capture = Capture(), engine = UnverifiedEngine(kind: kind)
            let microphone = ExplanationMicrophone(permissions: permissions, capture: capture)
            await #expect(throws: ExplanationMicrophoneError.cacheOnlyEngineRequired) {
                try await microphone.start(selection: .installedLocal(engine))
            }
            #expect(permissions.micRequests == 0 && capture.generations.isEmpty)
            let calls = await engine.calls, preparations = await engine.preparations
            #expect(calls == 0 && preparations == 0)
        }
    }

    @Test func realWhisperKitCacheOnlyEntryRefusesUnloadedInstanceWithoutPreparation() async throws {
        let engine = WhisperKitEngine()
        #expect(engine.availabilityWithoutLoading() == .notDownloaded)
        await #expect(throws: TranscriptionError.notReady(.whisperKit)) {
            try await engine.transcribeWithoutLoading(samples: [0], hints: [], language: nil)
        }
        #expect(engine.availabilityWithoutLoading() == .notDownloaded)
    }

    @Test func actualCapturePolicyRejectsInvalidFormatsAndEnforcesNinetySeconds() {
        #expect(!SpeechInput.validInputFormat(sampleRate: 0, channels: 1))
        #expect(!SpeechInput.validInputFormat(sampleRate: 1, channels: 1))
        #expect(!SpeechInput.validInputFormat(sampleRate: .nan, channels: 1))
        #expect(!SpeechInput.validInputFormat(sampleRate: 48_000, channels: 0))
        #expect(SpeechInput.validInputFormat(sampleRate: 48_000, channels: 2))
        let policy = SpeechInput.CapturePolicy.explanation
        #expect(policy.strictDeviceSelection && policy.cancelOnConfigurationChange)
        #expect(policy.failure(elapsed: 89, storedSamples: 0, incomingSamples: 16_000) == nil)
        #expect(policy.failure(elapsed: 90, storedSamples: 0, incomingSamples: 1) == .durationLimit)
        #expect(policy.failure(elapsed: 1, storedSamples: 90 * 16_000, incomingSamples: 1) == .sampleLimit)
        #expect(!SpeechInput.CapturePolicy(maximumSeconds: .infinity).isValid)
        #expect(!SpeechInput.CapturePolicy(maximumSamples: 90 * 16_000 + 1).isValid)
    }

    @Test func cancelledLocalInferenceKeepsItsSlotAndRejectsLateTranscript() async throws {
        let capture = Capture(), engine = Engine(held: true)
        let microphone = ExplanationMicrophone(permissions: Permissions(), capture: capture)
        try await microphone.start(selection: .installedLocal(engine))
        let finishing = Task { try await microphone.finish() }
        defer { finishing.cancel(); microphone.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await engine.waiting), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await engine.waiting)
        microphone.cancel()
        await #expect(throws: ExplanationMicrophoneError.busy) { try await microphone.start() }
        await engine.release()
        do { _ = try await finishing.value; Issue.record("Cancelled inference published old transcript") }
        catch is CancellationError {}
        catch let error as ExplanationMicrophoneError { #expect(error == .staleTurn) }
        #expect(microphone.partial.isEmpty && microphone.state == .idle)
        try await microphone.start()
        microphone.cancel()
    }
}
