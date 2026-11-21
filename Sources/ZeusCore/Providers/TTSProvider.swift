import Foundation

public struct Synthesis: Sendable {
    public var chunks: AsyncThrowingStream<AudioChunk, Error>
    /// Stops the in-flight request. A second call is harmless.
    public var cancel: @Sendable () -> Void
    public init(chunks: AsyncThrowingStream<AudioChunk, Error>, cancel: @escaping @Sendable () -> Void) {
        self.chunks = chunks
        self.cancel = cancel
    }
}

public protocol TTSProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func listVoices(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws -> [ProviderVoice]
    func synthesize(text: String, voice: ProviderVoice, credential: ProviderCredential, using transport: any ProviderHTTPTransport) -> Synthesis?
    func validate(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws
    func cancel()
}

public extension TTSProvider {
    /// Stateless adapters cancel through the `Synthesis` they returned.
    func cancel() {}
}

public protocol LocalVoiceSpeaking: Sendable {
    func speak(_ text: String) async -> Data
}

/// The Mac voice (`AVSpeechSynthesizer`). Used only after Zeus's local voice is unavailable.
public protocol SystemSpeechSpeaking: Sendable {
    func speak(_ text: String) async -> Data
}

public struct SilentSystemSpeech: SystemSpeechSpeaking {
    public init() {}
    public func speak(_ text: String) async -> Data { Data() }
}

enum ProviderJSON {
    static func data(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }

    static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

final class SynthesisTask: @unchecked Sendable {
    var cancel: @Sendable () -> Void = {}
}
