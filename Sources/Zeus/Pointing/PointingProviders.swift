import AVFoundation
import Foundation
import ZeusCore

// The replaceable adapter seam for the pointing assistant. Three paths sit behind two existing
// protocols: `ExplanationModelProviding` (vision reasoning, streamed scene events) and
// `SpeechOutputProvider` (one clip per beat). Nothing here logs a key, a prompt, a transcript,
// an image or a response. Keys come only from the Keychain.

// MARK: Credentials and health

enum PointingCredentials {
    private nonisolated static func first(_ accounts: [String]) -> String? {
        for account in accounts {
            if let value = Keychain.get(account)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
    }
    nonisolated static var anthropicKey: String? { first(["assistant.key.anthropic", "cloud.key.anthropic"]) }
    nonisolated static var openAIKey: String? { first(["assistant.key.openAI", "openai-tts.api-key", "cloud.key.openai"]) }
    nonisolated static var elevenLabsKey: String? { first(["elevenlabs.api-key", "assistant.key.elevenLabs", "cloud.key.elevenlabs"]) }

    /// Presence only. The Zeus setup path counts when the Any LLM endpoint is fully configured.
    static func available(anyLLMComplete: Bool) -> Set<PointingProviderPath> {
        var paths: Set<PointingProviderPath> = []
        if anthropicKey != nil, elevenLabsKey != nil { paths.insert(.anthropicElevenLabs) }
        if openAIKey != nil { paths.insert(.openAI) }
        if anyLLMComplete { paths.insert(.zeusSetup) }
        return paths
    }
}

/// A cheap authenticated metadata call per path, cached for a minute. No prompt or content is sent.
@MainActor
final class PointingProviderHealth {
    static let lifetime: TimeInterval = 60
    private var cache: [PointingProviderPath: (ok: Bool, at: TimeInterval)] = [:]
    private let now: () -> TimeInterval
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }

    func results(for paths: [PointingProviderPath]) async -> [PointingProviderPath: Bool] {
        let current = now()
        var out: [PointingProviderPath: Bool] = [:]
        var stale: [PointingProviderPath] = []
        for path in paths {
            if let hit = cache[path], current - hit.at < Self.lifetime { out[path] = hit.ok } else { stale.append(path) }
        }
        let anthropic = PointingCredentials.anthropicKey, openAI = PointingCredentials.openAIKey
        let probed: [(PointingProviderPath, Bool)] = await withTaskGroup(of: (PointingProviderPath, Bool).self) { group in
            for path in stale {
                group.addTask { (path, await Self.probe(path, anthropicKey: anthropic, openAIKey: openAI)) }
            }
            var all: [(PointingProviderPath, Bool)] = []
            for await item in group { all.append(item) }
            return all
        }
        for (path, ok) in probed { cache[path] = (ok, current); out[path] = ok }
        return out
    }

    func invalidate(_ path: PointingProviderPath) { cache[path] = nil }

    private nonisolated static func probe(_ path: PointingProviderPath, anthropicKey: String?, openAIKey: String?) async -> Bool {
        var request: URLRequest
        switch path {
        case .anthropicElevenLabs:
            guard let anthropicKey else { return false }
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!, timeoutInterval: 3)
            request.setValue(anthropicKey, forHTTPHeaderField: "x-api-key")
            request.setValue(PointingAnthropicProvider.version, forHTTPHeaderField: "anthropic-version")
        case .openAI:
            guard let openAIKey else { return false }
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!, timeoutInterval: 3)
            request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        case .zeusSetup:
            return true // A user-chosen endpoint is not probed here; a failure falls through at request time.
        }
        request.httpMethod = "GET"
        let session = URLSession(configuration: PointingHTTP.configuration(timeout: 3), delegate: ExplanationNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}

enum PointingHTTP {
    nonisolated static func configuration(timeout: TimeInterval) -> URLSessionConfiguration {
        let options = URLSessionConfiguration.ephemeral
        options.httpShouldSetCookies = false; options.httpCookieStorage = nil; options.urlCache = nil
        options.urlCredentialStorage = nil
        options.timeoutIntervalForRequest = timeout; options.timeoutIntervalForResource = max(timeout, 180)
        return options
    }

    /// Up to 4 KB of an error body, lowercased by the classifier. Never logged.
    nonisolated static func errorBody(_ bytes: URLSession.AsyncBytes) async -> String {
        var data = Data()
        do { for try await byte in bytes { data.append(byte); if data.count >= 4096 { break } } } catch {}
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: Reasoning adapters

/// Anthropic Messages API with an image and streaming.
/// Verified 2026-11-10 against https://platform.claude.com/docs/en/build-with-claude/vision
/// (image content block `{type:"image",source:{type:"base64",media_type:"image/jpeg",data}}`, image
/// before text, 10 MB base64 limit) and https://platform.claude.com/docs/en/build-with-claude/streaming
/// (`"stream": true`, SSE, `x-api-key` header).
@MainActor
final class PointingAnthropicProvider: ExplanationModelProviding {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    // Verify: the streaming docs now show `anthropic-version: 2026-10-21`. This uses 2023-06-01 like
    // AnthropicAPIProvider, which the API still accepts. Re-check before shipping.
    nonisolated static let version = "2023-06-01"
    private let key: () -> String?
    init(key: @escaping () -> String? = { PointingCredentials.anthropicKey }) { self.key = key }

    static func model(defaults: UserDefaults = .standard) -> String {
        // Sonnet at most (the owner's model cap). An override is still gated by the cap.
        if let override = defaults.string(forKey: "pointing.anthropic.model")?.trimmingCharacters(in: .whitespaces),
           !override.isEmpty, ModelCap.isAllowed(override) { return override }
        return ModelCap.httpModel(.anthropic, tier: .deep) ?? "claude-sonnet-4-5"
    }

    static func request(_ input: ExplanationModelRequest, key: String, model: String) throws -> URLRequest {
        try ExplanationSceneReducer.validate(input.scene)
        guard input.scene.revision < ExplanationLimits.revision, input.pointing != nil,
              input.prompt.utf8.count <= 16_384, !input.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.history.count <= ExplanationHistory.maxMessages,
              !key.utf8.contains(where: { $0 < 32 || $0 == 127 }), key.utf8.count <= 8192,
              let allowed = ModelCap.gatedHTTPModel(model) else { throw ExplanationProviderError.invalidRequest }
        let (instructions, reference) = try ExplanationHTTPProvider.prompt(for: input)
        var content: [[String: Any]] = []
        if let snapshot = input.snapshot {
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                                        "data": snapshot.jpegData.base64EncodedString()]])
        }
        content.append(["type": "text", "text": reference])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": allowed, "max_tokens": 4096, "stream": true, "system": instructions,
            "messages": [["role": "user", "content": content]],
        ] as [String: Any])
        guard request.httpBody!.count <= 12_582_912 else { throw ExplanationProviderError.invalidRequest }
        return request
    }

    func respond(_ input: ExplanationModelRequest,
                 receive: @escaping @MainActor (ExplanationEvent) async throws -> Void) async throws {
        try Task.checkCancellation()
        guard let key = key(), !key.isEmpty else { throw ExplanationProviderError.classified(.auth, provider: "Anthropic") }
        let request = try Self.request(input, key: key, model: Self.model())
        let events = Self.stream(request, sessionID: input.scene.sessionID, turnID: input.turnID,
                                 sceneID: input.scene.sceneID, baseRevision: input.scene.revision,
                                 profile: input.pointing.map { .v2(candidateIDs: $0.candidateIDs) } ?? .v1)
        for try await event in events {
            try Task.checkCancellation()
            try await receive(event)
        }
    }

    /// The byte loop runs off the main actor and hands validated events over; the consumer
    /// applies them on the main actor. A turn is at most 64 small events, so the buffer is bounded.
    nonisolated static func stream(_ request: URLRequest, sessionID: UUID, turnID: UUID, sceneID: UUID,
                                   baseRevision: Int, profile: ExplanationWireProfile) -> AsyncThrowingStream<ExplanationEvent, Error> {
        AsyncThrowingStream(ExplanationEvent.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                let session = URLSession(configuration: PointingHTTP.configuration(timeout: 60),
                                         delegate: ExplanationNoRedirects(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ExplanationProviderError.invalidResponse }
                    guard http.statusCode == 200 else {
                        let body = await PointingHTTP.errorBody(bytes)
                        throw ExplanationProviderError.classified(.classify(httpStatus: http.statusCode, body: body), provider: "Anthropic")
                    }
                    var parser = try ExplanationAnthropicStream(sessionID: sessionID, turnID: turnID, sceneID: sceneID,
                                                                baseRevision: baseRevision, profile: profile)
                    var line = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        line.append(byte)
                        guard byte == 10 else { continue }
                        for event in try parser.append(line) { continuation.yield(event) }
                        line.removeAll(keepingCapacity: true)
                    }
                    if !line.isEmpty { _ = try parser.append(line) }
                    try parser.finish()
                    continuation.finish()
                } catch { continuation.finish(throwing: mapped(error)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated static func mapped(_ error: Error) -> Error {
        if error is CancellationError || error is ExplanationProviderError { return error }
        if let url = error as? URLError {
            if url.code == .cancelled { return CancellationError() }
            let kind = PointingFailureKind.classify(urlErrorCode: url.code.rawValue)
            return ExplanationProviderError.classified(kind == .unknown ? .invalidResponse : kind, provider: "Anthropic")
        }
        if case ExplanationAnthropicStream.Failure.providerError(let type)? = error as? ExplanationAnthropicStream.Failure {
            return ExplanationProviderError.classified(.classify(anthropicErrorType: type), provider: "Anthropic")
        }
        return ExplanationProviderError.classified(.invalidResponse, provider: "Anthropic")
    }
}

/// Tries each path in order. A failure before any scene event arrived moves to the next path;
/// after the first event the turn cannot restart without replaying the scene, so it fails visibly.
@MainActor
final class PointingModelRouter: ExplanationModelProviding {
    private(set) var activePath: PointingProviderPath?
    /// Paths for the next turn, set by `PointingProviders.prepareTurn`.
    var order: [PointingProviderPath] = []
    var onFirstToken: ((PointingProviderPath, Double) -> Void)?
    var onFailure: ((PointingProviderPath, Error) -> Void)?
    private let adapters: [PointingProviderPath: any ExplanationModelProviding]
    private let now: () -> TimeInterval

    init(anyLLM: @escaping ExplanationHTTPProvider.Configuration, localOnly: @escaping () -> Bool,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        adapters = [
            .anthropicElevenLabs: PointingAnthropicProvider(),
            .openAI: ExplanationHTTPProvider(configuration: {
                let model = UserDefaults.standard.string(forKey: "pointing.openai.model")
                let chosen = (model?.isEmpty == false && ModelCap.isAllowed(model!)) ? model! : (ModelCap.httpModel(.openAI, tier: .deep) ?? "gpt-4o")
                // Verify: Chat Completions image_url content parts; the vision guide shows only the Responses format.
                return (AnyLLMConfig(baseURL: "https://api.openai.com/v1", model: chosen), PointingCredentials.openAIKey)
            }, displayName: "OpenAI"),
            .zeusSetup: ExplanationHTTPProvider(configuration: anyLLM, localOnly: localOnly, displayName: "Your model"),
        ]
    }

    func respond(_ request: ExplanationModelRequest,
                 receive: @escaping @MainActor (ExplanationEvent) async throws -> Void) async throws {
        var lastError: Error = ExplanationProviderError.notConfigured
        for path in order {
            guard let adapter = adapters[path] else { continue }
            activePath = path
            let started = now()
            var received = false
            do {
                try await adapter.respond(request) { [self] event in
                    if !received { received = true; onFirstToken?(path, now() - started) }
                    try await receive(event)
                }
                return
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                onFailure?(path, error)
                if received { throw error }
                lastError = error
            }
        }
        throw lastError
    }
}

// MARK: Speech adapters

enum PointingPCM {
    /// Raw 16-bit little-endian mono PCM to a prepared clip, through the same bounded sink and
    /// validation as system speech.
    @MainActor
    static func prepare(_ request: ExplanationSpeechRequest, pcm16: Data, sampleRate: Double,
                        alignment: @escaping @Sendable (Double) -> [ExplanationAlignmentMark] = { _ in [] }) async throws -> ExplanationPreparedAudio {
        let frames = pcm16.count / 2
        guard frames > 0, let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let end = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1),
              let target = buffer.int16ChannelData?[0] else { throw ExplanationAudioError.noAudio }
        buffer.frameLength = AVAudioFrameCount(frames)
        end.frameLength = 0
        pcm16.withUnsafeBytes { raw in
            if let base = raw.baseAddress { memcpy(target, base, frames * 2) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let sink = try ExplanationPCMSink(request: request, alignment: alignment) { result in
                    continuation.resume(with: result)
                }
                sink.receive(buffer)
                sink.receive(end)
            } catch { continuation.resume(throwing: error) }
        }
    }
}

/// ElevenLabs text to speech with character timestamps.
/// Verified 2026-11-10 against https://elevenlabs.io/docs/api-reference/text-to-speech/stream-with-timestamps :
/// `POST /v1/text-to-speech/{voice_id}/stream/with-timestamps`, query `output_format` (`pcm_24000`),
/// body `text`/`model_id`/`voice_settings`, response chunks `{audio_base64, alignment{characters,
/// character_start_times_seconds, character_end_times_seconds}}`.
@MainActor
final class PointingElevenLabsSpeech: SpeechOutputProvider {
    private let key: () -> String?
    init(key: @escaping () -> String? = { PointingCredentials.elevenLabsKey }) { self.key = key }

    static func request(text: String, key: String, voiceID: String) throws -> URLRequest {
        guard !text.isEmpty, text.utf8.count <= ExplanationLimits.speech, !key.isEmpty,
              !voiceID.isEmpty, voiceID.allSatisfy({ $0.isLetter || $0.isNumber }),
              var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream/with-timestamps")
        else { throw ExplanationAudioError.invalidSpeech }
        components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Verify: that the flash model supports the with-timestamps endpoint, and whether alignment
        // times in later chunks are cumulative (assumed) or restart per chunk.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, "model_id": ElevenLabsVoice.model,
            "voice_settings": ElevenLabsVoice.voiceSettings(for: .plain),
        ] as [String: Any])
        return request
    }

    func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio {
        try Task.checkCancellation()
        guard let key = key() else { throw ExplanationAudioError.unavailable }
        let voice = ElevenLabsVoice.savedVoiceID() ?? ElevenLabsVoice.defaultVoiceID
        let urlRequest = try Self.request(text: request.speech.text, key: key, voiceID: voice)
        let clip = try await Self.fetch(urlRequest)
        try Task.checkCancellation()
        return try await PointingPCM.prepare(request, pcm16: clip.pcm, sampleRate: 24_000) { duration in
            PointingSpeechAlignment.wordMarks(characters: clip.characters, starts: clip.starts, ends: clip.ends, duration: duration)
        }
    }

    struct Clip: Sendable { var pcm: Data; var characters: [String]; var starts: [Double]; var ends: [Double] }

    nonisolated static func fetch(_ request: URLRequest) async throws -> Clip {
        let session = URLSession(configuration: PointingHTTP.configuration(timeout: 20), delegate: ExplanationNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do { (bytes, response) = try await session.bytes(for: request) }
        catch let error as URLError {
            let kind = PointingFailureKind.classify(urlErrorCode: error.code.rawValue)
            throw ExplanationProviderError.classified(kind, provider: "ElevenLabs")
        }
        guard let http = response as? HTTPURLResponse else { throw ExplanationProviderError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = await PointingHTTP.errorBody(bytes)
            throw ExplanationProviderError.classified(.classify(httpStatus: http.statusCode, body: body), provider: "ElevenLabs")
        }
        var splitter = JSONObjectSplitter()
        var clip = Clip(pcm: Data(), characters: [], starts: [], ends: [])
        var pending = Data()
        func drain() throws {
            for object in try splitter.append(pending) {
                let chunk = try JSONDecoder().decode(ElevenLabsTimestampChunk.self, from: object)
                clip.pcm.append(chunk.audio)
                if let alignment = chunk.alignment, alignment.characters.count == alignment.starts.count,
                   alignment.characters.count == alignment.ends.count {
                    clip.characters += alignment.characters; clip.starts += alignment.starts; clip.ends += alignment.ends
                }
                guard clip.pcm.count <= 8 * 1_024 * 1_024 else { throw ExplanationAudioError.resourceLimit }
            }
            pending.removeAll(keepingCapacity: true)
        }
        for try await byte in bytes {
            pending.append(byte)
            if pending.count >= 4096 { try Task.checkCancellation(); try drain() }
        }
        try drain()
        guard !clip.pcm.isEmpty, !splitter.hasPartial else { throw ExplanationAudioError.noAudio }
        return clip
    }
}

/// OpenAI text to speech as raw PCM.
/// Verified 2026-11-10 against https://developers.openai.com/api/docs/guides/text-to-speech :
/// `POST /v1/audio/speech`, `response_format: "pcm"` is 24 kHz 16-bit signed little-endian with no
/// header, streamed with chunked transfer. The page lists `tts-1` as deprecated, so the default
/// model is `gpt-4o-mini-tts` (also scheduled for shutdown on 2027-01-06 per that page).
@MainActor
final class PointingOpenAISpeech: SpeechOutputProvider {
    private let key: () -> String?
    init(key: @escaping () -> String? = { PointingCredentials.openAIKey }) { self.key = key }

    static func request(text: String, key: String, defaults: UserDefaults = .standard) throws -> URLRequest {
        guard !text.isEmpty, text.utf8.count <= ExplanationLimits.speech, !key.isEmpty else { throw ExplanationAudioError.invalidSpeech }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": defaults.string(forKey: "pointing.openai.ttsModel") ?? "gpt-4o-mini-tts",
            "input": text, "voice": defaults.string(forKey: "voice.openai.voice") ?? "alloy",
            "response_format": "pcm",
        ] as [String: Any])
        return request
    }

    func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio {
        try Task.checkCancellation()
        guard let key = key() else { throw ExplanationAudioError.unavailable }
        let urlRequest = try Self.request(text: request.speech.text, key: key)
        let pcm = try await Self.fetch(urlRequest)
        try Task.checkCancellation()
        return try await PointingPCM.prepare(request, pcm16: pcm, sampleRate: 24_000)
    }

    nonisolated static func fetch(_ request: URLRequest) async throws -> Data {
        let session = URLSession(configuration: PointingHTTP.configuration(timeout: 20), delegate: ExplanationNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do { (bytes, response) = try await session.bytes(for: request) }
        catch let error as URLError {
            throw ExplanationProviderError.classified(PointingFailureKind.classify(urlErrorCode: error.code.rawValue), provider: "OpenAI")
        }
        guard let http = response as? HTTPURLResponse else { throw ExplanationProviderError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = await PointingHTTP.errorBody(bytes)
            throw ExplanationProviderError.classified(.classify(httpStatus: http.statusCode, body: body), provider: "OpenAI")
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count & 0xFFF == 0 { try Task.checkCancellation() }
            guard data.count <= 8 * 1_024 * 1_024 else { throw ExplanationAudioError.resourceLimit }
        }
        return data
    }
}

/// Speech for the active path, falling back to the installed system voice when the vendor voice
/// fails (so the user always hears the answer). The fallback is reported, never silent.
@MainActor
final class PointingSpeechRouter: SpeechOutputProvider {
    var path: PointingProviderPath = .zeusSetup
    var onFallback: ((PointingProviderPath, Error) -> Void)?
    private let system: any SpeechOutputProvider
    private let elevenLabs: any SpeechOutputProvider
    private let openAI: any SpeechOutputProvider

    init(system: any SpeechOutputProvider = SystemExplanationSpeechOutput(),
         elevenLabs: any SpeechOutputProvider = PointingElevenLabsSpeech(),
         openAI: any SpeechOutputProvider = PointingOpenAISpeech()) {
        self.system = system; self.elevenLabs = elevenLabs; self.openAI = openAI
    }

    func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio {
        let vendor: (any SpeechOutputProvider)?
        switch path {
        case .anthropicElevenLabs: vendor = elevenLabs
        case .openAI: vendor = openAI
        case .zeusSetup: vendor = nil
        }
        guard let vendor else { return try await system.render(request) }
        do { return try await vendor.render(request) }
        catch {
            if error is CancellationError || Task.isCancelled { throw error }
            onFallback?(path, error)
            return try await system.render(request)
        }
    }
}

// MARK: Orchestration of the three paths

/// Owns the routers, the in-memory latency book and the per-turn path order.
@MainActor
final class PointingProviders {
    let model: PointingModelRouter
    let speech: PointingSpeechRouter
    private(set) var book = PointingLatencyBook()
    private let health: PointingProviderHealth
    private let anyLLMComplete: () -> Bool
    private let choice: () -> PointingProviderChoice
    private let now: () -> TimeInterval
    /// The path whose speech the user is hearing this turn, for the time-to-first-audio record.
    private(set) var activeSpeechPath: PointingProviderPath?
    private var firstTokenByPath: [PointingProviderPath: Double] = [:]

    init(anyLLM: @escaping ExplanationHTTPProvider.Configuration, localOnly: @escaping () -> Bool,
         anyLLMComplete: @escaping () -> Bool, choice: @escaping () -> PointingProviderChoice = { PointingSettings.providerChoice },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         health: PointingProviderHealth = PointingProviderHealth()) {
        model = PointingModelRouter(anyLLM: anyLLM, localOnly: localOnly)
        speech = PointingSpeechRouter()
        self.anyLLMComplete = anyLLMComplete; self.choice = choice; self.now = now; self.health = health
        model.onFirstToken = { [weak self] path, seconds in
            self?.firstTokenByPath[path] = seconds
            self?.speech.path = path
            self?.activeSpeechPath = path
        }
        model.onFailure = { [weak self] path, _ in
            guard let self else { return }
            self.book.recordFailure(path, at: self.now())
            self.health.invalidate(path)
        }
    }

    /// Chooses and orders the paths for the next turn. Returns them (empty means nothing is configured).
    @discardableResult
    func prepareTurn() async -> [PointingProviderPath] {
        let credentials = PointingCredentials.available(anyLLMComplete: anyLLMComplete())
        let selected = choice()
        let candidates = selected.path.map { [$0] } ?? PointingProviderSelector.defaultOrder.filter { credentials.contains($0) }
        let healthy = selected == .auto ? await health.results(for: candidates) : [:]
        let order = PointingProviderSelector.order(choice: selected, credentials: credentials, health: healthy,
                                                   latency: book, now: now())
        model.order = order
        speech.path = order.first ?? .zeusSetup
        activeSpeechPath = order.first
        firstTokenByPath = [:]
        return order
    }

    /// Time from key release to the first audio the user heard. Numbers only.
    func recordFirstAudio(secondsSinceRelease: Double) {
        guard let path = activeSpeechPath else { return }
        book.record(path, firstToken: firstTokenByPath[path], firstAudio: secondsSinceRelease)
    }

    func resetMeasurements() { book.reset() }
}
