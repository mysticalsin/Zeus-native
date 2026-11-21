import Foundation
import Testing
@testable import ZeusCore

@Suite("Voice catalogs and the Gemini TTS provider")
struct VoiceCatalogTests {
    private let openAITen = ["alloy", "ash", "ballad", "cedar", "coral", "echo", "marin", "sage", "shimmer", "verse"]
    private let geminiThirty = [
        "Achernar", "Achird", "Algenib", "Algieba", "Alnilam", "Aoede", "Autonoe", "Callirrhoe", "Charon", "Despina",
        "Enceladus", "Erinome", "Fenrir", "Gacrux", "Iapetus", "Kore", "Laomedeia", "Leda", "Orus", "Puck",
        "Pulcherrima", "Rasalgethi", "Sadachbia", "Sadaltager", "Schedar", "Sulafat", "Umbriel", "Vindemiatrix",
        "Zephyr", "Zubenelgenubi",
    ]

    private func geminiConfig(voice: String = "Kore", key: String = "AIza-test-key-123") -> GeminiTTSRequest.Config {
        GeminiTTSRequest.Config(model: "gemini-3.8-flash-lite-tts", voice: voice, apiKey: key)
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Catalogs

    @Test func openAICatalogHasTheTenCatalogVoicesAndKeepsTheOlderOnes() {
        let ids = OpenAIVoiceCatalog.voices.map(\.id)
        #expect(Set(openAITen).isSubset(of: Set(ids)))
        #expect(ids.contains("onyx"))
        #expect(ids.count == Set(ids).count)
        #expect(ids.contains(UltronCloudVoice.openAIVoice))
    }

    @Test func legacyOpenAIModelsOfferOnlyTheirSmallerVoiceSet() {
        let legacy = OpenAIVoiceCatalog.voices(forModel: "tts-1").map(\.id)
        #expect(!legacy.contains("marin") && !legacy.contains("cedar"))
        #expect(legacy.contains("onyx") && legacy.contains("alloy"))
        let current = OpenAIVoiceCatalog.voices(forModel: "gpt-4o-mini-tts").map(\.id)
        #expect(current.contains("marin") && current.contains("cedar"))
    }

    @Test func geminiCatalogHasExactlyTheThirtyPrebuiltVoices() {
        let names = GeminiVoiceCatalog.voices.map(\.id)
        #expect(names.count == 30)
        #expect(Set(names) == Set(geminiThirty))
    }

    @Test func storedVoiceFallsBackToTheDefaultWhenUnknown() {
        #expect(GeminiVoiceCatalog.resolve(stored: "Puck") == "Puck")
        #expect(GeminiVoiceCatalog.resolve(stored: "puck") == "Puck")
        #expect(GeminiVoiceCatalog.resolve(stored: "not-a-voice") == GeminiVoiceCatalog.defaultVoice)
        #expect(GeminiVoiceCatalog.resolve(stored: nil) == GeminiVoiceCatalog.defaultVoice)
    }

    // MARK: Gemini request

    @Test func geminiRequestUsesTheInteractionsEndpointAndHeaderKey() throws {
        let request = try #require(GeminiTTSRequest.makeRequest(text: "Hello there.", config: geminiConfig()))
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test-key-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.query == nil)
    }

    @Test func geminiBodyCarriesTextVoiceAndRawPCMFormat() throws {
        let request = try #require(GeminiTTSRequest.makeRequest(text: "Hello there.", config: geminiConfig(voice: "Puck")))
        let body = try jsonBody(request)
        #expect(body["model"] as? String == "gemini-3.8-flash-lite-tts")
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.first?["type"] as? String == "user_input")
        let content = try #require(input.first?["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "text")
        #expect(content.first?["text"] as? String == "Hello there.")
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "audio")
        #expect(format["mime_type"] as? String == "audio/l16")
        #expect(format["sample_rate"] as? Int == 24_000)
        let generation = try #require(body["generation_config"] as? [String: Any])
        let speech = try #require(generation["speech_config"] as? [[String: Any]])
        #expect(speech.first?["voice"] as? String == "Puck")
    }

    @Test func geminiKeyNeverAppearsInTheBodyOrTheLogSummary() throws {
        let request = try #require(GeminiTTSRequest.makeRequest(text: "Hello there.", config: geminiConfig()))
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!body.contains("AIza-test-key-123"))
        let summary = GeminiTTSRequest.logSummary(config: geminiConfig())
        #expect(!summary.contains("AIza-test-key-123"))
        #expect(summary.contains("gemini-3.8-flash-lite-tts") && summary.contains("Kore"))
    }

    @Test func geminiRequestNeedsAKeyAndText() {
        #expect(GeminiTTSRequest.makeRequest(text: "Hi", config: geminiConfig(key: "")) == nil)
        #expect(GeminiTTSRequest.makeRequest(text: "", config: geminiConfig()) == nil)
    }

    @Test func geminiResponseYieldsTheLastAudioBlockAsPCM() throws {
        let first = Data([1, 2, 3, 4]).base64EncodedString()
        let last = Data([9, 8, 7, 6, 5, 4]).base64EncodedString()
        let json = """
        {"steps":[{"type":"model_output","content":[{"type":"audio","data":"\(first)"},{"type":"audio","data":"\(last)"}]}]}
        """
        let pcm = try #require(GeminiTTSRequest.pcm(fromResponse: Data(json.utf8)))
        #expect(pcm == Data([9, 8, 7, 6, 5, 4]))
    }

    @Test func geminiResponseWithoutAudioOrWithAnErrorIsNil() {
        #expect(GeminiTTSRequest.pcm(fromResponse: Data(#"{"steps":[{"type":"thought","content":[]}]}"#.utf8)) == nil)
        #expect(GeminiTTSRequest.pcm(fromResponse: Data(#"{"error":{"code":400,"message":"bad"}}"#.utf8)) == nil)
        #expect(GeminiTTSRequest.pcm(fromResponse: Data("not json".utf8)) == nil)
    }

    @Test func geminiWAVReplyHasItsHeaderStripped() throws {
        let samples = Data([10, 0, 20, 0, 30, 0])
        let wav = GeminiTTSRequest.wav(fromPCM: samples)
        let json = #"{"steps":[{"type":"model_output","content":[{"type":"audio","data":"\#(wav.base64EncodedString())"}]}]}"#
        #expect(GeminiTTSRequest.pcm(fromResponse: Data(json.utf8)) == samples)
    }

    @Test func wavWrapperDescribes24kHzMono16BitPCM() throws {
        let samples = Data(repeating: 7, count: 48)
        let wav = GeminiTTSRequest.wav(fromPCM: samples)
        #expect(wav.count == 44 + 48)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        func u32(_ at: Int) -> UInt32 { wav[at..<(at + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        func u16(_ at: Int) -> UInt16 { UInt16(wav[at]) | UInt16(wav[at + 1]) << 8 }
        #expect(u16(20) == 1 && u16(22) == 1 && u16(34) == 16)
        #expect(u32(24) == 24_000 && u32(28) == 48_000)
        #expect(u32(40) == 48 && u32(4) == 36 + 48)
        #expect(wav.suffix(48) == samples)
    }

    // MARK: Provider selection

    @Test func geminiIsAProviderWithItsOwnKeychainAccount() {
        #expect(VoiceTTSProvider.allCases.contains(.gemini))
        #expect(VoiceTTSProvider.gemini.keychainAccount == "gemini-tts.api-key")
        #expect(VoiceProviderKeychain.accounts(for: .gemini) == ["gemini-tts.api-key"])
        #expect(VoiceTTSProvider.gemini.needsKey)
    }

    @Test func noGeminiKeyLeavesProviderSelectionUnchanged() {
        let without = VoiceProviderFallback.Availability(
            kokoroReady: true, chatterboxReady: false, elevenLabsConfigured: true, openAIConfigured: true)
        #expect(VoiceProviderFallback.chain(chosen: .elevenLabs, availability: without) == [.elevenLabs, .kokoro, .openAICompatible])
        let a = UltronEngineAvailability(elevenLabsConfigured: true, openAIConfigured: true, kokoroReady: true)
        #expect(UltronEngineRouter.chain(choice: .auto, availability: a).map(\.engine) == [.kokoro, .system])
        #expect(UltronEngineRouter.chain(choice: .auto, availability: UltronEngineAvailability()).map(\.engine) == [.system])
        #expect(UltronEngineAvailability().skipReason(.gemini) == "no Gemini key")
    }

    @Test func elevenLabsStaysFirstWhenAGeminiKeyIsSaved() {
        let a = UltronEngineAvailability(elevenLabsConfigured: true, openAIConfigured: true, geminiConfigured: true, kokoroReady: true)
        #expect(UltronEngineRouter.chain(choice: .auto, availability: a).map(\.engine) == [.kokoro, .system])
        let only = UltronEngineAvailability(geminiConfigured: true)
        #expect(UltronEngineRouter.chain(choice: .auto, availability: only).map(\.engine) == [.system])
        let chosen = UltronEngineAvailability(elevenLabsConfigured: true, geminiConfigured: true)
        #expect(UltronEngineRouter.chain(choice: .fixed(.gemini), availability: chosen).map(\.engine) == [.gemini, .system])
        let paused = UltronEngineAvailability(geminiConfigured: true, geminiPaused: true)
        #expect(UltronEngineRouter.chain(choice: .auto, availability: paused).map(\.engine) == [.system])
    }

    @Test func geminiJoinsTheProviderFallbackAfterOpenAI() {
        let all = VoiceProviderFallback.Availability(
            kokoroReady: true, chatterboxReady: true, elevenLabsConfigured: true, openAIConfigured: true, geminiConfigured: true)
        #expect(VoiceProviderFallback.chain(chosen: .elevenLabs, availability: all)
                == [.elevenLabs, .kokoro, .chatterbox, .openAICompatible, .gemini])
    }

    @Test func previewSentenceIsShortAndOriginal() {
        #expect(!VoiceCatalogPreview.sentence.isEmpty)
        #expect(VoiceCatalogPreview.sentence.count < 120)
    }
}
