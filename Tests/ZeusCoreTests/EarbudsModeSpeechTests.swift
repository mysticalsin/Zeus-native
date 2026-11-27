import Testing
@testable import ZeusCore

@Suite struct EarbudsModeSpeechTests {
    @Test func turningAModeOffDoesNotSayOffOn() {
        #expect(EarbudsWords.spoken(.changed(.noiseCancelling)) == "Noise cancelling on.")
        #expect(EarbudsWords.spoken(.changed(.transparency)) == "Transparency on.")
        #expect(EarbudsWords.spoken(.changed(.adaptive)) == "Adaptive on.")
        #expect(EarbudsWords.spoken(.changed(.off)) == "Listening mode off.")
        #expect(EarbudsWords.spoken(.stayed(.off)) == "Listening mode stayed off.")
        #expect(EarbudsWords.spoken(.stayed(.transparency)) == "Listening mode stayed on Transparency.")
    }
}
