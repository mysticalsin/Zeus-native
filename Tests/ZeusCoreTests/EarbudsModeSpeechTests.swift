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

    @Test func hiddenDetailsDoNotSpeakTheBattery() {
        let cue = EarbudsCueFacts(name: "Secret Buds", connected: true, parts: [
            EarbudsPartReading(part: .left, level: .fresh(80)),
        ])
        let hidden = EarbudsWords.spoken(cue, hideDetails: true)
        #expect(hidden == "Earbuds connected.")
        #expect(!hidden.contains("80"))
        #expect(!hidden.contains("Secret"))
        #expect(EarbudsWords.spoken(cue, hideDetails: false) == "Secret Buds connected. Left 80 percent.")
    }
}
