import Foundation
import ZeusCore

/// An engine that hears the audio while it is being recorded, so little is left to do on release.
protocol StreamingTranscriptionEngine: TranscriptionEngine {
    func openStream(hints: [String], language: String?) -> any TranscriptionStream
}

/// One live session: feed 16 kHz samples as they arrive, then `finish` for the final text.
protocol TranscriptionStream: AnyObject, Sendable {
    func send(_ samples: [Float])
    func finish() async throws -> String
    func cancel()
}

/// The cloud engines' keys, from the existing Keychain slots, read only when an engine runs.
/// They are never logged and never shown back.
@MainActor
enum CloudKeys {
    nonisolated static func key(for kind: TranscriptionEngineKind) -> String? {
        guard let account = kind.keyAccount,
              let value = Keychain.get(account)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    nonisolated static func has(_ kind: TranscriptionEngineKind) -> Bool { key(for: kind) != nil }

    /// Saves through the same owners as the Voice and Assistant pages, so their state stays right.
    static func save(_ key: String, for kind: TranscriptionEngineKind) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch kind {
        case .elevenLabs:
            VoiceSettings.shared.elevenKeyDraft = trimmed
            VoiceSettings.shared.saveElevenKey()
        case .openAI:
            AssistantAccount.shared.save(trimmed, for: .openAI)
        default: break
        }
    }
}

// MARK: OpenAI

/// OpenAI gpt-transcribe: the recording goes up once the person stops talking (the file
/// endpoint; the realtime one needs client-side turn detection). Audio leaves this Mac.
final class OpenAITranscribeEngine: TranscriptionEngine, @unchecked Sendable {
    let kind = TranscriptionEngineKind.openAI
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func availability() async -> EngineAvailability { CloudKeys.has(kind) ? .ready : .needsKey }

    func prepare(progress: (@Sendable (Double) -> Void)?) async throws {}

    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.noSpeech }
        guard let key = CloudKeys.key(for: kind) else { throw CloudTranscriptionError.missingKey(OpenAITranscription.provider) }
        let wav = PCM16.wav(samples)
        guard wav.count < 25_000_000 else { throw CloudTranscriptionError.server(OpenAITranscription.provider, "The recording is over 25 MB.") }
        let request = OpenAITranscription.request(wav: wav, apiKey: key, prompt: DictationVocabularyPrompt.whisperPrompt(terms: hints),
                                                  keywords: hints, language: language)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw CloudTranscriptionError.timeout(OpenAITranscription.provider)
        } catch {
            throw CloudTranscriptionError.network(OpenAITranscription.provider)
        }
        return try OpenAITranscription.parse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

// MARK: ElevenLabs

/// ElevenLabs Scribe v2 Realtime: streams over a WebSocket while the person speaks, commits on
/// release. Audio leaves this Mac.
final class ElevenLabsScribeEngine: StreamingTranscriptionEngine, @unchecked Sendable {
    let kind = TranscriptionEngineKind.elevenLabs

    func availability() async -> EngineAvailability { CloudKeys.has(kind) ? .ready : .needsKey }

    func prepare(progress: (@Sendable (Double) -> Void)?) async throws {}

    func openStream(hints: [String], language: String?) -> any TranscriptionStream {
        ElevenLabsStream(apiKey: CloudKeys.key(for: kind), language: language, keyterms: hints)
    }

    /// A recording that already ended (history, files, voice turns): stream it all, then commit.
    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.noSpeech }
        let stream = openStream(hints: hints, language: language)
        stream.send(samples)
        return try await stream.finish()
    }
}

final class ElevenLabsStream: TranscriptionStream, @unchecked Sendable {
    private let lock = NSLock()
    private let session = URLSession(configuration: .ephemeral)
    private var task: URLSessionWebSocketTask?
    private var pending = Data()
    private var transcript = RealtimeTranscript()
    private var failure: CloudTranscriptionError?
    private var finishing = false
    private var committed = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var closed = false

    init(apiKey: String?, language: String?, keyterms: [String]) {
        guard let apiKey else {
            failure = .missingKey(ElevenLabsRealtime.provider)
            return
        }
        let url = ElevenLabsRealtime.url(language: language, keyterms: keyterms)
        let task = session.webSocketTask(with: ElevenLabsRealtime.request(url: url, apiKey: apiKey))
        self.task = task
        task.resume()
        receive()
    }

    func send(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let pcm = PCM16.encode(samples)
        let chunks: [Data] = lock.withLock {
            guard !closed, failure == nil else { return [] }
            pending.append(pcm)
            var ready: [Data] = []
            while pending.count >= ElevenLabsRealtime.chunkBytes {
                ready.append(Data(pending.prefix(ElevenLabsRealtime.chunkBytes)))
                pending.removeFirst(ElevenLabsRealtime.chunkBytes)
            }
            return ready
        }
        for chunk in chunks { sendText(ElevenLabsRealtime.audioChunk(chunk, commit: false)) }
    }

    func finish() async throws -> String {
        let (rest, alreadyFailed) = lock.withLock { () -> (Data, Bool) in
            finishing = true
            defer { pending = Data() }
            return (pending, failure != nil)
        }
        if !alreadyFailed {
            if !rest.isEmpty { sendText(ElevenLabsRealtime.audioChunk(rest, commit: false)) }
            sendText(ElevenLabsRealtime.audioChunk(Data(), commit: true))
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let done = lock.withLock { () -> Bool in
                    if committed || failure != nil { return true }
                    waiter = continuation
                    return false
                }
                if done { continuation.resume(); return }
                DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in self?.wake() }
            }
        }
        cancel()
        let (text, failure, committed) = lock.withLock { (transcript.text, self.failure, self.committed) }
        if let failure { throw failure }
        if !committed && text.isEmpty { throw CloudTranscriptionError.timeout(ElevenLabsRealtime.provider) }
        return text
    }

    func cancel() {
        let task = lock.withLock { () -> URLSessionWebSocketTask? in
            closed = true
            defer { self.task = nil }
            return self.task
        }
        task?.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
        wake()
    }

    private func sendText(_ text: String) {
        guard let task = lock.withLock({ self.task }) else { return }
        task.send(.string(text)) { [weak self] error in
            if error != nil { self?.fail(.network(ElevenLabsRealtime.provider)) }
        }
    }

    private func receive() {
        guard let task = lock.withLock({ self.task }) else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                self.handle(ElevenLabsRealtime.parse(text))
                self.receive()
            case .success(.data(let data)):
                self.handle(ElevenLabsRealtime.parse(String(decoding: data, as: UTF8.self)))
                self.receive()
            case .success:
                self.receive()
            case .failure:
                self.fail(.network(ElevenLabsRealtime.provider))
            }
        }
    }

    private func handle(_ event: ElevenLabsRealtime.Event) {
        switch event {
        case .failure(let type, _) where type == "insufficient_audio_activity":
            // Nothing worth transcribing: an empty result, not a broken engine.
            lock.withLock { committed = true }
            wake()
        case .failure(let type, let message):
            fail(ElevenLabsRealtime.error(type: type, message: message))
        case .committed:
            let wakeNow = lock.withLock { () -> Bool in
                transcript.apply(event)
                if finishing { committed = true }
                return finishing
            }
            if wakeNow { wake() }
        default:
            lock.withLock { transcript.apply(event) }
        }
    }

    private func fail(_ error: CloudTranscriptionError) {
        lock.withLock {
            if failure == nil, !closed { failure = error }
        }
        wake()
    }

    private func wake() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { waiter = nil }
            return waiter
        }
        continuation?.resume()
    }
}
