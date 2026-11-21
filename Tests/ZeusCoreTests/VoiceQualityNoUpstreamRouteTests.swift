import Testing
@testable import ZeusCore

@Suite struct VoiceQualityNoUpstreamRouteTests {
    @Test func automaticStaysSyntheticWithoutTheParkedRoute() {
        let keys = VoiceQualitySpeakKeys(elevenLabs: true, openAI: true, gemini: true, googleCloud: true, kokoroReady: true)
        #expect(VoiceQualityRoute.selection(choice: .automatic, keys: keys, preset: .elevenLabsStudio) == .synthetic)
        #expect(VoiceQualityRoute.activeVoiceID(choice: .automatic, keys: keys, preset: .elevenLabsStudio) == "zeus.synthetic")
        #expect(VoiceQualityRoute.activeVoiceID(choice: .automatic, keys: keys, preset: .elevenLabsStudio) == VoiceSpeakAllowlist.syntheticID)
    }
}
