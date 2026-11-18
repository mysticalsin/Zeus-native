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
        let suite = UserDefaults(suiteName: "zeus-openai-retire-" + UUID().uuidString)!
        if let model { suite.set(model, forKey: "pointing.openai.ttsModel") }
        return suite
    }

    private func request() -> ExplanationSpeechRequest {
        .init(event: .init(sessionID: UUID(), turnID: UUID(), sceneID: UUID(), sequence: 0,
                          baseRevision: 0, revision: 1, beatID: "beat", speech: .init(chunkID: "chunk", text: "A synthetic beat."), cues: []))
    }

    private struct SystemRan: Error {}

    @MainActor
    private final class StubSystem: SpeechOutputProvider {
        func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio { throw SystemRan() }
    }

    @Test func pointingOpenAISpeechBuildsNoRequestAfterShutdown() async {
        var keyReads = 0
        let speech = PointingOpenAISpeech(key: { keyReads += 1; return "sk-test" }, now: { self.after }, defaults: defaults())
        await #expect(throws: ExplanationAudioError.unavailable) { _ = try await speech.render(request()) }
        #expect(keyReads == 0)
    }

    @Test func pointingOpenAISpeechIsUnchangedBeforeShutdown() throws {
        #expect(!PointingOpenAISpeech.isRetired(defaults: defaults(), now: before))
        #expect(PointingOpenAISpeech.isRetired(defaults: defaults(), now: after))
        #expect(PointingOpenAISpeech.isRetired(defaults: defaults("tts-1"), now: after))
        #expect(!PointingOpenAISpeech.isRetired(defaults: defaults("my-local-tts"), now: after))
        let built = try PointingOpenAISpeech.request(text: "Hello", key: "sk-test", defaults: defaults())
        #expect(built.url?.path == "/v1/audio/speech")
    }

    @Test func pointingRouterFallsBackToTheSystemVoiceAfterShutdown() async {
        var fallbacks = 0
        let openAI = PointingOpenAISpeech(key: { "sk-test" }, now: { self.after }, defaults: defaults())
        let router = PointingSpeechRouter(system: StubSystem(), openAI: openAI)
        router.path = .openAI
        router.onFallback = { _, _ in fallbacks += 1 }
        await #expect(throws: SystemRan.self) { _ = try await router.render(request()) }
        #expect(fallbacks == 1)
    }

    @Test func openAIConfigIsNilAfterShutdownEvenWithASavedModel() {
        #expect(OpenAITTSVoice.isRetired(defaults: defaults(), now: before) == false)
        let suite = UserDefaults(suiteName: "zeus-openai-retire-" + UUID().uuidString)!
        #expect(OpenAITTSVoice.isRetired(defaults: suite, now: after))
        suite.set("my-local-tts", forKey: "voice.openai.model")
        #expect(!OpenAITTSVoice.isRetired(defaults: suite, now: after))
    }

    @Test func previewDoesNotCallOpenAIAfterShutdown() {
        let model = VoicePreviewModel()
        model.toggle(.openAICompatible, voice: "alloy", now: after)
        #expect(model.activeID == nil)
        #expect(!model.loading)
        #expect(model.message == "Ended January 6, 2027")
    }
}
