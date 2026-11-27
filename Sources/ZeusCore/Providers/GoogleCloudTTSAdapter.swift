import Foundation

/// Google Cloud Text-to-Speech, API-key authentication.
///
/// - Synthesize: https://cloud.google.com/text-to-speech/docs/reference/rest/v1/text/synthesize
/// - Voices: https://cloud.google.com/text-to-speech/docs/reference/rest/v1/voices/list
/// - API key header: https://cloud.google.com/docs/authentication/api-keys
///
/// v1 `text:synthesize` returns one base64 `audioContent` payload, not a byte stream. Zeus still
/// yields that payload as the first audio chunk so callers start playback on the first yield.
/// The key is sent as `X-Goog-Api-Key` and is never placed in the URL. Validation is the voices list.
public struct GoogleCloudTTSAdapter: TTSProvider, Sendable {
    public static let id = "google-cloud-tts"
    public static let descriptor = ProviderDescriptor(
        id: id,
        displayName: "Google Cloud Text-to-Speech",
        kind: .tts,
        credentialFields: [CredentialField(id: ProviderCredentialLocation.account, label: "API key", masked: true)],
        docsURL: URL(string: "https://cloud.google.com/text-to-speech/docs/reference/rest/v1/text/synthesize")!,
        capabilities: [.listVoices, .streamingSynthesis, .validateCredential]
    )
    public var descriptor: ProviderDescriptor { Self.descriptor }
    public init() {}

    public static func synthesizeRequest(text: String, voice: ProviderVoice, credential: ProviderCredential) -> ProviderHTTPRequest? {
        guard let key = credential.value(ProviderCredentialLocation.account),
              let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize"),
              let body = ProviderJSON.data([
                "input": ["text": text],
                "voice": ["languageCode": languageCode(for: voice), "name": voice.id],
                "audioConfig": ["audioEncoding": "LINEAR16", "sampleRateHertz": 24_000],
              ]) else { return nil }
        return ProviderHTTPRequest(url: url, method: "POST", headers: headers(key), body: body)
    }

    public static func voicesRequest(credential: ProviderCredential) -> ProviderHTTPRequest? {
        guard let key = credential.value(ProviderCredentialLocation.account),
              let url = URL(string: "https://texttospeech.googleapis.com/v1/voices") else { return nil }
        return ProviderHTTPRequest(url: url, method: "GET", headers: headers(key), body: nil)
    }

    public static func validationRequest(credential: ProviderCredential) -> ProviderHTTPRequest? {
        voicesRequest(credential: credential)
    }

    public func listVoices(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws -> [ProviderVoice] {
        guard let request = Self.voicesRequest(credential: credential) else { throw ProviderFailure.missingCredential }
        let response = try await transport.send(request)
        guard (200...299).contains(response.status) else { throw ProviderFailure.fromHTTPStatus(response.status, validating: true) }
        guard let json = ProviderJSON.object(response.body), let rows = json["voices"] as? [[String: Any]] else {
            throw ProviderFailure.invalidResponse
        }
        return rows.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            let language = (row["languageCodes"] as? [String])?.first
            return ProviderVoice(id: name, name: name, language: language)
        }
    }

    public func synthesize(text: String, voice: ProviderVoice, credential: ProviderCredential, using transport: any ProviderHTTPTransport) -> Synthesis? {
        guard let request = Self.synthesizeRequest(text: text, voice: voice, credential: credential) else { return nil }
        let task = SynthesisTask()
        let chunks = AsyncThrowingStream<AudioChunk, Error> { continuation in
            let work = Task {
                do {
                    try Task.checkCancellation()
                    let response = try await transport.send(request)
                    try Task.checkCancellation()
                    guard (200...299).contains(response.status) else {
                        continuation.finish(throwing: ProviderFailure.fromHTTPStatus(response.status))
                        return
                    }
                    guard let json = ProviderJSON.object(response.body),
                          let encoded = json["audioContent"] as? String,
                          let audio = Data(base64Encoded: encoded), !audio.isEmpty else {
                        continuation.finish(throwing: ProviderFailure.invalidResponse)
                        return
                    }
                    continuation.yield(AudioChunk(data: audio, index: 0, isLast: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ProviderFailure.wrap(error))
                }
            }
            task.cancel = {
                work.cancel()
                continuation.finish(throwing: ProviderFailure.cancelled)
            }
            continuation.onTermination = { _ in work.cancel() }
        }
        return Synthesis(chunks: chunks, cancel: { task.cancel() })
    }

    public func validate(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws {
        guard let request = Self.validationRequest(credential: credential) else { throw ProviderFailure.missingCredential }
        let response = try await transport.send(request)
        guard (200...299).contains(response.status) else { throw ProviderFailure.fromHTTPStatus(response.status, validating: true) }
    }

    static func languageCode(for voice: ProviderVoice) -> String {
        if let language = voice.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty { return language }
        let parts = voice.id.split(separator: "-")
        if parts.count >= 2 { return "\(parts[0])-\(parts[1])" }
        return "en-US"
    }

    private static func headers(_ key: String) -> [String: String] {
        ["X-Goog-Api-Key": key, "Content-Type": "application/json"]
    }
}

enum ProviderSynthesis {
    static func stream(request: ProviderHTTPRequest, using transport: any ProviderHTTPTransport, make: @escaping @Sendable (Data, Int) -> AudioChunk) -> Synthesis {
        let task = SynthesisTask()
        // Open the transport here so an in-memory stream buffers its chunks before the caller waits.
        let source = transport.stream(request)
        let chunks = AsyncThrowingStream<AudioChunk, Error> { continuation in
            let work = Task {
                do {
                    var status = 0
                    var index = 0
                    for try await event in source {
                        try Task.checkCancellation()
                        switch event {
                        case .status(let code):
                            status = code
                        case .chunk(let data):
                            guard (200...299).contains(status), !data.isEmpty else { continue }
                            continuation.yield(make(data, index))
                            index += 1
                        }
                    }
                    if !(200...299).contains(status) {
                        continuation.finish(throwing: ProviderFailure.fromHTTPStatus(status))
                    } else if index == 0 {
                        continuation.finish(throwing: ProviderFailure.invalidResponse)
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: ProviderFailure.wrap(error))
                }
            }
            task.cancel = {
                work.cancel()
                continuation.finish(throwing: ProviderFailure.cancelled)
            }
            continuation.onTermination = { _ in work.cancel() }
        }
        return Synthesis(chunks: chunks, cancel: { task.cancel() })
    }
}
