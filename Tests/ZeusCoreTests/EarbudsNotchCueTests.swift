import Testing
@testable import ZeusCore

@Suite struct EarbudsNotchCueTests {
    @Test func aHiddenConnectShowsConnectedAndSpeaksEarbuds() {
        let cue = EarbudsNotchCue.make(
            EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
                EarbudsPartReading(part: .left, level: .fresh(80)),
            ]),
            hideDetails: true
        )
        #expect(cue.text == "Connected")
        #expect(cue.connected)
        #expect(cue.spoken == "Earbuds connected.")
        #expect(!cue.spoken.contains("80"))
        #expect(!cue.spoken.contains("Pro Max"))
        #expect(cue.duration == EarbudsCuePolicy.connectedDuration)
    }

    @Test func aShownChargeNamesTheBudAndTheNotchKeepsTheLevels() {
        let cue = EarbudsNotchCue.make(
            EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
                EarbudsPartReading(part: .left, level: .fresh(80)),
                EarbudsPartReading(part: .right, level: .unknown),
            ]),
            hideDetails: false
        )
        #expect(cue.text == "L 80%")
        #expect(cue.spoken.contains("Pro Max Buds"))
        #expect(cue.spoken.contains("80"))
        #expect(cue.duration == 4)
    }

    @Test func aDisconnectShowsDisconnectedForThreeSeconds() {
        let cue = EarbudsNotchCue.make(EarbudsCueFacts(name: "Pro Max Buds", connected: false), hideDetails: false)
        #expect(cue.text == "Disconnected")
        #expect(!cue.connected)
        #expect(cue.spoken == "Pro Max Buds disconnected.")
        #expect(cue.duration == EarbudsCuePolicy.disconnectedDuration)
    }
}
