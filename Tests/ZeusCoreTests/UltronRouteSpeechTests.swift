import Testing
@testable import ZeusCore

@Suite("Voice route speech")
struct UltronRouteSpeechTests {
    @Test func theMacVoiceIsNamedLastWhenACloudVoiceLeads() {
        let availability = UltronEngineAvailability(elevenLabsConfigured: true, kokoroReady: true)
        let decisions = UltronEngineRouter.chain(choice: .auto, availability: availability)
        #expect(decisions.map(\.engine) == [.elevenLabs, .kokoro, .system])
        #expect(UltronEngineRouter.spokenOrder(decisions) == "Zeus speaks with ElevenLabs. If that fails, Kokoro, then Mac voice.")
    }

    @Test func theMacVoiceAloneDoesNotInventACloudFallback() {
        let decisions = UltronEngineRouter.chain(choice: .fixed(.system), availability: UltronEngineAvailability(elevenLabsConfigured: true, kokoroReady: true))
        #expect(decisions.map(\.engine) == [.system])
        #expect(UltronEngineRouter.spokenOrder(decisions) == "Zeus speaks with Mac voice.")
    }

    @Test func anEmptyRouteSaysNoVoiceIsReady() {
        #expect(UltronEngineRouter.spokenOrder([]) == "No voice is ready.")
    }
}
