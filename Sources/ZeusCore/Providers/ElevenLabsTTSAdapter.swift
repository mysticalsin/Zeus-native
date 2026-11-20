import Foundation

/// ElevenLabs streaming speech.
///
/// - Stream: https://elevenlabs.io/docs/api-reference/text-to-speech/stream
/// - Voices: https://elevenlabs.io/docs/api-reference/voices/search (GET /v1/voices)
/// - Validate: https://elevenlabs.io/docs/api-reference/user/get
///
/// The key travels in the `xi-api-key` header. `eleven_flash_v2_5` is the low-latency model so the
/// first audio chunk can start before the clip is finished. Requests are HTTPS only.
public struct ElevenLabsTTSAdapter: TTSProvider, Sendable {
    public static let id = "elevenlabs"
    public static let descriptor = ProviderDescriptor(
        id: id,
        displayName: "ElevenLabs",
        kind: .tts,
        credentialFields: [CredentialField(id: ProviderCredentialLocation.account, label: "API key", masked: true)],
        docsURL: URL(string: "https://elevenlabs.io/docs/api-reference/text-to-speech/stream")!,
        capabilities: [.listVoices, .streamingSynthesis, .validateCredential]
    )
    public var descriptor: ProviderDescriptor { Self.descriptor }
    public init() {}

    public static func streamRequest(text: String, voiceID: String, credential: ProviderCredential) -> ProviderHTTPRequest? {
        guard let key = credential.value(ProviderCredentialLocation.account), let voice = pathComponent(voiceID),
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream"),
              let body = ProviderJSON.data(["text": text, "model_id": "eleven_flash_v2_5"]) else { return nil }
        return ProviderHTTPRequest(url: url, method: "POST", headers: headers(key, accept: "audio/mpeg"), body: body)
    }

    public static func voicesRequest(credential: ProviderCredential) -> ProviderHTTPRequest? {
        guard let key = credential.value(ProviderCredentialLocation.account),
              let url = URL(string: "https://api.elevenlabs.io/v1/voices") else { return nil }
        return ProviderHTTPRequest(url: url, method: "GET", headers: headers(key, accept: nil), body: nil)
    }

    public static func validationRequest(credential: ProviderCredential) -> ProviderHTTPRequest? {
        guard let key = credential.value(ProviderCredentialLocation.account),
              let url = URL(string: "https://api.elevenlabs.io/v1/user") else { return nil }
        return ProviderHTTPRequest(url: url, method: "GET", headers: headers(key, accept: nil), body: nil)
    }

    public func listVoices(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws -> [ProviderVoice] {
        guard let request = Self.voicesRequest(credential: credential) else { throw ProviderFailure.missingCredential }
        let response = try await transport.send(request)
        guard (200...299).contains(response.status) else { throw ProviderFailure.fromHTTPStatus(response.status, validating: true) }
        guard let json = ProviderJSON.object(response.body), let rows = json["voices"] as? [[String: Any]] else {
            throw ProviderFailure.invalidResponse
        }
        return rows.compactMap { row in
            guard let id = row["voice_id"] as? String, let name = row["name"] as? String else { return nil }
            return ProviderVoice(id: id, name: name, language: nil)
        }
    }

    public func synthesize(text: String, voice: ProviderVoice, credential: ProviderCredential, using transport: any ProviderHTTPTransport) -> Synthesis? {
        guard let request = Self.streamRequest(text: text, voiceID: voice.id, credential: credential) else { return nil }
        return ProviderSynthesis.stream(request: request, using: transport) { data, index in
            AudioChunk(data: data, index: index, isLast: false)
        }
    }

    public func validate(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws {
        guard let request = Self.validationRequest(credential: credential) else { throw ProviderFailure.missingCredential }
        let response = try await transport.send(request)
        guard (200...299).contains(response.status) else { throw ProviderFailure.fromHTTPStatus(response.status, validating: true) }
    }

    private static func headers(_ key: String, accept: String?) -> [String: String] {
        var headers = ["xi-api-key": key, "Content-Type": "application/json"]
        if let accept { headers["Accept"] = accept }
        return headers
    }

    /// Voice ids are a single path segment. A slash or `..` would retarget the request.
    static func pathComponent(_ voiceID: String) -> String? {
        let trimmed = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains(".."), !trimmed.contains("\\"),
              trimmed.unicodeScalars.allSatisfy({ CharacterSet.urlPathAllowed.contains($0) }),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !encoded.isEmpty else { return nil }
        return encoded
    }
}
