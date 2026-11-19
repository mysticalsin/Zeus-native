import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("OpenAI speech retirement in the app")
struct OpenAISpeechRetirementAppTests {
    private let before = Date(timeIntervalSince1970: 1_799_193_599)
    private let after = Date(timeIntervalSince1970: 1_799_193_600)

    private func defaults(_ model: String? = nil) -> UserDefaults {
        let suite = UserDefaults(suiteName: NSTemporaryDirectory() + "zeus-openai-retire-" + UUID().uuidString)!
        if let model { suite.set(model, forKey: "pointing.openai.ttsModel") }
        return suite
    }

    private func request() -> ExplanationSpeechRequest {
        .init(event: .init(sessionID: UUID(), turnID: UUID(), sceneID: UUID(), sequence: 0,
                          baseRevision: 0, revision: 1, beatID: "beat", speech: .init(chunkID: "chunk", text: "A synthetic beat."), cues: []))
    }

    private struct SystemRan: Error {}
    private struct Transported: Error {}

    @MainActor
    private final class StubSystem: SpeechOutputProvider {
        func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio { throw SystemRan() }
    }

    @Test func pointingOpenAISpeechReadsNoKeyAndSendsNothingAfterShutdown() async {
        var keyReads = 0, sent = 0
        let speech = PointingOpenAISpeech(key: { keyReads += 1; return "sk-test" }, now: { self.after }, defaults: defaults(),
                                          transport: { _ in sent += 1; throw Transported() })
        await #expect(throws: ExplanationAudioError.unavailable) { _ = try await speech.render(request()) }
        #expect(keyReads == 0)
        #expect(sent == 0)
    }

    @Test func pointingOpenAISpeechSendsThroughTheSeamBeforeShutdown() async {
        var keyReads = 0, sent = 0
        let speech = PointingOpenAISpeech(key: { keyReads += 1; return "sk-test" }, now: { self.before }, defaults: defaults(),
                                          transport: { request in
            sent += 1
            #expect(request.url?.path == "/v1/audio/speech")
            throw Transported()
        })
        await #expect(throws: Transported.self) { _ = try await speech.render(request()) }
        #expect(keyReads == 1)
        #expect(sent == 1)
    }

    @Test func pointingRetirementFollowsTheExactModelIds() {
        #expect(!PointingOpenAISpeech.isRetired(defaults: defaults(), now: before))
        #expect(PointingOpenAISpeech.isRetired(defaults: defaults(), now: after))
        #expect(PointingOpenAISpeech.isRetired(defaults: defaults("tts-1"), now: after))
        #expect(!PointingOpenAISpeech.isRetired(defaults: defaults("gpt-4o-mini-tts-2026-06-01"), now: after))
        #expect(!PointingOpenAISpeech.isRetired(defaults: defaults("my-local-tts"), now: after))
    }

    @Test func pointingRouterFallsBackToTheSystemVoiceWithoutSendingAfterShutdown() async {
        var fallbacks = 0, sent = 0, keyReads = 0
        let openAI = PointingOpenAISpeech(key: { keyReads += 1; return "sk-test" }, now: { self.after }, defaults: defaults(),
                                          transport: { _ in sent += 1; throw Transported() })
        let router = PointingSpeechRouter(system: StubSystem(), openAI: openAI)
        router.path = .openAI
        router.onFallback = { _, _ in fallbacks += 1 }
        await #expect(throws: SystemRan.self) { _ = try await router.render(request()) }
        #expect(fallbacks == 1)
        #expect(sent == 0)
        #expect(keyReads == 0)
    }

    private func voiceDefaults(model: String? = nil, base: String? = nil) -> UserDefaults {
        let suite = UserDefaults(suiteName: NSTemporaryDirectory() + "zeus-openai-retire-" + UUID().uuidString)!
        if let model { suite.set(model, forKey: "voice.openai.model") }
        if let base { suite.set(base, forKey: "voice.openai.baseURL") }
        return suite
    }

    @Test func openAIConfigIsNilAfterShutdownAndPresentBeforeWithAKey() {
        let d = voiceDefaults()
        #expect(OpenAITTSVoice.config(defaults: d, now: before, key: { "sk-test" }) != nil)
        #expect(OpenAITTSVoice.config(defaults: d, now: before, key: { nil }) == nil)
        #expect(OpenAITTSVoice.config(defaults: d, now: after, key: { "sk-test" }) == nil)
        let hd = voiceDefaults(model: "tts-1-hd")
        #expect(OpenAITTSVoice.config(defaults: hd, now: after, key: { "sk-test" }) == nil)
    }

    @Test func aCustomBaseURLKeepsWorkingAfterShutdown() {
        let d = voiceDefaults(model: "tts-1", base: "http://localhost:8000/v1")
        #expect(!OpenAITTSVoice.isRetired(defaults: d, now: after))
        #expect(OpenAITTSVoice.config(defaults: d, now: after, key: { "sk-test" })?.baseURL.host == "localhost")
        let own = voiceDefaults(model: "tts-1", base: "https://api.openai.com/v1")
        #expect(OpenAITTSVoice.isRetired(defaults: own, now: after))
    }

    @Test func previewDoesNotRenderOrCallOpenAIAfterShutdown() {
        let model = VoicePreviewModel()
        var rendered = 0
        model.toggle(.openAICompatible, voice: "alloy", now: after, defaults: voiceDefaults(),
                     renderer: { _, _ in rendered += 1; return nil })
        #expect(model.activeID == nil)
        #expect(!model.loading)
        #expect(model.message == "Ended January 6, 2027")
        #expect(rendered == 0)
    }
}
