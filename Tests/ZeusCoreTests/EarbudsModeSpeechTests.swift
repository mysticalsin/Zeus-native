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

    @Test func hiddenDetailsDoNotDrawTheBattery() {
        let cue = EarbudsCueFacts(name: "Secret Buds", connected: true, parts: [
            EarbudsPartReading(part: .left, level: .fresh(80)),
            EarbudsPartReading(part: .case, level: .lastKnown(60)),
        ])
        #expect(EarbudsWords.cueStatus(cue, hideDetails: true) == [EarbudsCueLine(text: "Connected")])
        #expect(EarbudsWords.cueStatus(cue).contains { $0.text.contains("80") })
        let presence = EarbudsShown(id: "device-1", name: "Secret Buds", parts: cue.parts)
        let hidden = EarbudsPanelModel.make(presence: presence, mode: nil, hideDetails: true)
        #expect(hidden?.name == "Earbuds")
        #expect(hidden?.parts.isEmpty == true)
        #expect(EarbudsPanelModel.make(presence: presence, mode: nil, hideDetails: false)?.parts.isEmpty == false)
        let mode = EarbudsModeShown(
            outputUID: "uid",
            outputName: "Secret Buds",
            status: EarbudsModeStatus(current: .noiseCancelling, choices: [
                EarbudsModeChoice(mode: .noiseCancelling, available: true),
            ])
        )
        let modeOnly = EarbudsPanelModel.make(presence: nil, mode: mode, hideDetails: true)
        #expect(modeOnly?.name == "Earbuds")
        #expect(modeOnly?.parts.isEmpty == true)
        #expect(modeOnly?.capsules.isEmpty == false)
    }
}
