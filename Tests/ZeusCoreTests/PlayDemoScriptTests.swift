import Testing
@testable import ZeusCore

@Suite struct PlayDemoScriptTests {
    @Test func theListeningAndThinkingBeatsAreSpokenAndShown() {
        for step in [PlayDemoScript.listening, PlayDemoScript.thinking] {
            #expect(PlayDemoScript.ready(step))
            #expect(step.showsOnScreen)
            #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
            #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
        }
        #expect(PlayDemoScript.listening.bolt == "Listening")
        #expect(PlayDemoScript.thinking.bolt == "Thinking")
        #expect(PlayDemoScript.listening.spoken == "Hold the talk key, then speak. I'll listen.")
        #expect(PlayDemoScript.thinking.spoken == "One moment. I'm working out what to show you.")
    }

    @Test func theMenuBarDemoIsSpokenAndShown() {
        let step = PlayDemoScript.menuBar
        #expect(PlayDemoScript.ready(step))
        #expect(step.showsOnScreen)
        #expect(step.spoken == "That's me up here. Click the bolt anytime.")
        #expect(step.bolt == "Click the bolt anytime")
        #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
        #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
    }

    @Test func theApprovalDemoIsSpokenAndShown() {
        let step = PlayDemoScript.approval
        #expect(PlayDemoScript.ready(step))
        #expect(step.showsOnScreen)
        #expect(step.spoken == "This needs you. Approve or deny, or just say ok.")
        #expect(step.bolt == "Approve or deny, or say ok")
        #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
        #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
    }

    @Test func aStepThatIsNotDrawnIsNotReady() {
        let spokenOnly = PlayDemoScript.Step(
            spoken: "Click the bolt anytime",
            bolt: "Click the bolt anytime",
            showsOnScreen: false)
        #expect(PlayDemoScript.ready(spokenOnly) == false)
        let wall = PlayDemoScript.Step(
            spoken: "That's me up here.",
            bolt: String(repeating: "a", count: 41),
            showsOnScreen: true)
        #expect(PlayDemoScript.ready(wall) == false)
    }
}
