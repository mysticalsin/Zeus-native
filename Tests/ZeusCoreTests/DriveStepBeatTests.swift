import Testing
@testable import ZeusCore

@Suite struct DriveStepBeatTests {
    @Test func aClickIsSpokenAndShown() {
        let beat = DriveStepBeat.make(index: 2, count: 5, step: .click(DriveTarget(label: "File"), double: false))
        #expect(beat.spoken == "Step 2 of 5. Click “File”.")
        #expect(beat.bolt == "Click “File”")
        #expect(beat.bolt.count <= DriveStepBeat.boltLimit)
    }

    @Test func aPasswordFieldIsNotReadAloud() {
        let secret = "correct horse"
        let step = DriveStep.type(secret, into: DriveTarget(label: "Password", secure: true))
        let beat = DriveStepBeat.make(index: 1, count: 2, step: step)
        #expect(beat.spoken == nil)
        #expect(beat.bolt == "Secret")
        #expect(beat.bolt.contains(secret) == false)
        let set = DriveStepBeat.make(index: 1, count: 1, step: .setValue(DriveTarget(label: "API key"), "sk-live"))
        #expect(set.spoken == nil)
        #expect(set.bolt == "Secret")
        #expect(set.bolt.contains("sk-live") == false)
    }

    @Test func aLowCountStillSpeaksTheStep() {
        let beat = DriveStepBeat.make(index: 0, count: 0, step: .openApp("Safari"))
        #expect(beat.spoken == "Step 1 of 1. Open Safari.")
        #expect(beat.bolt == "Open Safari")
    }
}
